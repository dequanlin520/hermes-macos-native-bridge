#!/usr/bin/env python3
import argparse
import json
import locale
import os
import re
import sys
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

try:
    locale.setlocale(locale.LC_TIME, "C")
except locale.Error:
    pass

BOUNDARY_TOLERANCE_SECONDS = 2

TZ_ABBREVIATIONS = {
    "UTC": timezone.utc,
    "GMT": timezone.utc,
    "PST": timezone(timedelta(hours=-8), "PST"),
    "PDT": timezone(timedelta(hours=-7), "PDT"),
    "MST": timezone(timedelta(hours=-7), "MST"),
    "MDT": timezone(timedelta(hours=-6), "MDT"),
    "CST": timezone(timedelta(hours=-6), "CST"),
    "CDT": timezone(timedelta(hours=-5), "CDT"),
    "EST": timezone(timedelta(hours=-5), "EST"),
    "EDT": timezone(timedelta(hours=-4), "EDT"),
}

TIMESTAMP_RE = re.compile(
    r"^\s*(?P<stamp>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?)"
    r"(?:\s+(?P<zone>Z|UTC|GMT|[A-Z]{3,4}|[+-]\d{2}:?\d{2}))?"
    r"\s+(?P<rest>.+?)\s*$"
)


def fail(reason):
    raise SystemExit(reason)


def redact(value):
    value = re.sub(r"/Users/[^ \t:,'\"]+", "/Users/<redacted>", value)
    value = re.sub(
        r"/(?:Applications|Library|System|private|tmp|var|opt|usr|bin|sbin|Volumes)/[^ \t:,'\"]+",
        "/<path-redacted>",
        value,
    )
    value = re.sub(
        r"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\b",
        "<uuid>",
        value,
    )
    value = re.sub(r"\bPID\s+\d+\([^)]*\)", "PID <redacted>", value, flags=re.I)
    value = re.sub(
        r"\b(?:pid|process|proc|owner|user|uid|gid)=[^ \t,;:]+",
        lambda match: match.group(0).split("=")[0] + "=<redacted>",
        value,
        flags=re.I,
    )
    value = re.sub(r"'[^']*'", "'<redacted>'", value)
    value = re.sub(r'"[^"]*"', '"<redacted>"', value)
    return value[:240]


def parse_zone(zone_text):
    if not zone_text:
        return None
    if zone_text == "Z":
        return timezone.utc
    upper = zone_text.upper()
    if upper in TZ_ABBREVIATIONS:
        return TZ_ABBREVIATIONS[upper]
    normalized = zone_text.replace(":", "")
    if re.fullmatch(r"[+-]\d{4}", normalized):
        sign = 1 if normalized[0] == "+" else -1
        hours = int(normalized[1:3])
        minutes = int(normalized[3:5])
        return timezone(sign * timedelta(hours=hours, minutes=minutes), normalized)
    return None


def parse_pmset_timestamp(line):
    match = TIMESTAMP_RE.match(line)
    if not match:
        return None
    stamp = re.sub(r"\s+", " ", match.group("stamp"))
    zone = parse_zone(match.group("zone"))
    fmt = "%Y-%m-%d %H:%M:%S.%f" if "." in stamp else "%Y-%m-%d %H:%M:%S"
    try:
        parsed = datetime.strptime(stamp, fmt)
    except ValueError:
        return None
    if zone is None:
        parsed = parsed.astimezone()
    else:
        parsed = parsed.replace(tzinfo=zone)
    rest = match.group("rest").strip()
    pieces = re.split(r"\t+|\s{2,}", rest, maxsplit=1)
    if len(pieces) == 1:
        words = rest.split(maxsplit=1)
        domain = words[0]
        message = words[1] if len(words) > 1 else ""
    else:
        domain, message = pieces[0].strip(), pieces[1].strip()
    return int(parsed.timestamp()), domain, message


def classify_event(domain, message):
    normalized_domain = " ".join(domain.split())
    normalized_message = " ".join(message.split())
    combined = f"{normalized_domain} {normalized_message}".strip()
    lower = combined.lower()

    rejects = [
        ("rejected-maintenance-wake", ["maintenance", "wake maintenance"]),
        ("rejected-sleepservice", ["sleepservice"]),
        ("rejected-display-sleep", ["display sleep", "display is turned off", "preventuseridledisplaysleep"]),
        ("rejected-display-wake", ["display wake", "displaywake", "display is turned on"]),
        ("rejected-wake-request", ["wake request", "wakerequest", "wake requested", "scheduled wake"]),
        ("rejected-user-active", ["userisactive"]),
        ("rejected-assertions", ["assertions", "assertion"]),
        ("rejected-tcpkeepalive", ["tcpkeepalive"]),
    ]
    for reason, needles in rejects:
        if any(needle in lower for needle in needles):
            if reason == "rejected-tcpkeepalive" and re.search(
                r"\bSleep\b.*\bEntering DarkWake state\b.*\bSoftware Sleep\b",
                combined,
                re.I,
            ):
                continue
            return None, reason

    if re.search(r"\bSleep\b.*\bEntering Sleep state\b", combined, re.I):
        return "system-sleep", None
    if re.search(r"\bSleep\b.*\bSleep Entered\b", combined, re.I):
        return "system-sleep", None
    if re.search(r"\bSystem Sleep\b", combined, re.I):
        return "system-sleep", None
    if re.search(r"\bSleep\b.*\bEntering DarkWake state\b.*\bSoftware Sleep\b", combined, re.I):
        return "system-sleep", None

    if re.search(r"\bWake\b.*\bWake from Normal Sleep\b", combined, re.I):
        return "system-wake", None
    if re.search(r"\bWake\b.*\bDarkWake to FullWake\b", combined, re.I):
        return "system-wake", None
    if re.search(r"\bSystem Wake\b", combined, re.I):
        return "system-wake", None

    if "darkwake" in lower or "dark wake" in lower:
        return None, "rejected-darkwake"

    return None, "rejected-unclassified"


def read_checkpoint(path, expected_run_id):
    try:
        checkpoint = json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception:
        fail("power-log-boundary-invalid")
    if checkpoint.get("runIdentifier") != expected_run_id:
        fail("power-log-boundary-invalid")
    boundary = checkpoint.get("powerLogCheckpoint")
    if not isinstance(boundary, dict):
        fail("power-log-boundary-invalid")
    try:
        prepare_epoch = boundary["epochSeconds"]
        if not isinstance(prepare_epoch, int):
            fail("power-log-boundary-invalid")
        prepare_uptime = float(boundary["systemUptime"])
    except KeyError:
        fail("power-log-boundary-invalid")
    except (TypeError, ValueError):
        fail("invalid-uptime-evidence")
    return checkpoint, boundary, prepare_epoch, prepare_uptime


def analyze_lines(lines, prepare_epoch, resume_epoch):
    selected = []
    for raw_line in lines:
        parsed = parse_pmset_timestamp(raw_line)
        if parsed is None:
            continue
        epoch, domain, message = parsed
        kind, rejection = classify_event(domain, message)
        row = {
            "epochSeconds": epoch,
            "domain": redact(domain),
            "summary": redact(message),
        }
        if epoch < prepare_epoch - BOUNDARY_TOLERANCE_SECONDS:
            if kind in {"system-sleep", "system-wake"}:
                row["kind"] = "rejected-out-of-bounds"
                row["rejectionReason"] = "before-checkpoint"
                selected.append(row)
            continue
        if epoch > resume_epoch + BOUNDARY_TOLERANCE_SECONDS:
            if kind in {"system-sleep", "system-wake"}:
                row["kind"] = "rejected-out-of-bounds"
                row["rejectionReason"] = "after-resume"
                selected.append(row)
            continue
        if kind:
            row["kind"] = kind
        else:
            row["kind"] = "rejected"
            row["rejectionReason"] = rejection
        selected.append(row)
    return selected


def validate_events(events):
    ordered_system_events = [event for event in events if event["kind"] in {"system-sleep", "system-wake"}]
    sleep = next((event for event in ordered_system_events if event["kind"] == "system-sleep"), None)
    if ordered_system_events and ordered_system_events[0]["kind"] != "system-sleep":
        fail("invalid-system-event-order")
    if sleep is None:
        fail("system-sleep-missing")
    wake = next(
        (
            event
            for event in ordered_system_events
            if event["kind"] == "system-wake" and event["epochSeconds"] > sleep["epochSeconds"]
        ),
        None,
    )
    if wake is None:
        fail("system-wake-missing")
    return sleep, wake


def verify(args):
    checkpoint, boundary, prepare_epoch, prepare_uptime = read_checkpoint(args.checkpoint, args.run_id)
    try:
        resume_epoch = int(args.resume_epoch)
        resume_uptime = float(args.resume_uptime)
    except (TypeError, ValueError):
        fail("invalid-uptime-evidence")
    if resume_epoch < prepare_epoch:
        fail("power-log-boundary-invalid")
    if resume_uptime < prepare_uptime:
        fail("invalid-uptime-evidence")
    if (resume_epoch - prepare_epoch) + BOUNDARY_TOLERANCE_SECONDS < (resume_uptime - prepare_uptime):
        fail("invalid-uptime-evidence")

    events = analyze_lines(sys.stdin.read().splitlines(), prepare_epoch, resume_epoch)
    sleep, wake = validate_events(events)
    payload = {
        "schemaVersion": 1,
        "runIdentifier": args.run_id,
        "provider": "pmset -g log",
        "boundedInterval": {
            "toleranceSeconds": BOUNDARY_TOLERANCE_SECONDS,
            "checkpointEpochSeconds": prepare_epoch,
            "checkpointUTC": boundary.get("utcISO8601"),
            "checkpointLocalTimezoneOffset": boundary.get("localTimezoneOffset"),
            "resumeEpochSeconds": resume_epoch,
            "resumeUTC": args.resume_utc,
        },
        "systemSleepEpochSeconds": sleep["epochSeconds"],
        "systemWakeEpochSeconds": wake["epochSeconds"],
        "uptime": {
            "prepareSystemUptime": prepare_uptime,
            "resumeSystemUptime": resume_uptime,
        },
        "events": events,
    }
    target = Path(args.evidence)
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("w", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    directory_fd = os.open(str(target.parent), os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def diagnose(args):
    expected_run_id = args.run_id
    checkpoint_path = Path(args.checkpoint)
    if not checkpoint_path.exists():
        print("checkpoint=missing")
        if not args.fixture_log:
            return 0
        prepare_epoch = int(args.fixture_prepare_epoch)
        resume_epoch = int(args.fixture_resume_epoch)
    else:
        try:
            checkpoint = json.loads(checkpoint_path.read_text(encoding="utf-8"))
            expected_run_id = expected_run_id or checkpoint.get("runIdentifier", "")
            _, boundary, prepare_epoch, _ = read_checkpoint(checkpoint_path, expected_run_id)
        except SystemExit as error:
            print(f"checkpoint=invalid reason={error}")
            if not args.fixture_log:
                return 1
            prepare_epoch = int(args.fixture_prepare_epoch)
        except Exception:
            print("checkpoint=invalid reason=power-log-boundary-invalid")
            if not args.fixture_log:
                return 1
            prepare_epoch = int(args.fixture_prepare_epoch)
        resume_epoch = int(args.fixture_resume_epoch) if args.fixture_resume_epoch else int(time.time())

    if args.fixture_log:
        lines = Path(args.fixture_log).read_text(encoding="utf-8").splitlines()
    else:
        lines = sys.stdin.read().splitlines()
    print(f"checkpoint_epoch={prepare_epoch}")
    print(f"resume_epoch={resume_epoch}")
    print(f"tolerance_seconds={BOUNDARY_TOLERANCE_SECONDS}")
    for event in analyze_lines(lines, prepare_epoch, resume_epoch):
        rejection = event.get("rejectionReason", "")
        event_kind = {
            "system-sleep": "sleep",
            "system-wake": "wake",
            "rejected": "rejected",
            "rejected-out-of-bounds": "rejected",
        }.get(event["kind"], "unknown")
        shape = f"{event['domain']} {event['summary']}".strip()
        print(
            "candidate "
            f"event_epoch={event['epochSeconds']} "
            f"event_kind={event_kind} "
            f"rejection_reason={rejection or 'accepted'} "
            f"domain={event['domain']} "
            f"sanitized_message_shape={shape}"
        )
    return 0


def main():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    verify_parser = subparsers.add_parser("verify")
    verify_parser.add_argument("--checkpoint", required=True)
    verify_parser.add_argument("--evidence", required=True)
    verify_parser.add_argument("--run-id", required=True)
    verify_parser.add_argument("--resume-utc", required=True)
    verify_parser.add_argument("--resume-epoch", required=True)
    verify_parser.add_argument("--resume-uptime", required=True)
    diagnose_parser = subparsers.add_parser("diagnose")
    diagnose_parser.add_argument("--checkpoint", required=True)
    diagnose_parser.add_argument("--run-id")
    diagnose_parser.add_argument("--fixture-log")
    diagnose_parser.add_argument("--fixture-prepare-epoch")
    diagnose_parser.add_argument("--fixture-resume-epoch")
    args = parser.parse_args()
    if args.command == "verify":
        verify(args)
    elif args.command == "diagnose":
        return diagnose(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
