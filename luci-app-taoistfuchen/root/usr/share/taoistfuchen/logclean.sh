#!/bin/sh
# Periodic log cleanup for FakeHTTP / FakeSIP (run from cron).
# Keeps each /tmp log under a size cap by dropping the oldest lines, so the
# router's RAM is never filled even if a service logs a lot.

MAX_BYTES=131072   # trim once a log grows past 128 KB
KEEP_BYTES=65536   # keep roughly the most recent 64 KB

for f in /tmp/fakehttp.log /tmp/fakesip.log; do
	[ -f "$f" ] || continue

	size="$(wc -c < "$f" 2>/dev/null)"
	case "$size" in
		''|*[!0-9]*) continue ;;
	esac

	if [ "$size" -gt "$MAX_BYTES" ]; then
		# Truncate in place (same inode) so the running daemon keeps writing
		# to the same file: copy the recent tail back over the file.
		tail -c "$KEEP_BYTES" "$f" > "$f.tmp" 2>/dev/null && \
			cat "$f.tmp" > "$f" 2>/dev/null
		rm -f "$f.tmp" 2>/dev/null
	fi
done

exit 0
