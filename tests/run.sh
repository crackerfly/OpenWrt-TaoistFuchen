#!/bin/sh

set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

"$ROOT/tests/test_service_common.sh"
"$ROOT/tests/test_service_commands.sh"
"$ROOT/tests/test_upload.sh"
"$ROOT/tests/test_migration.sh"
"$ROOT/tests/test_theme_runtime.sh"
"$ROOT/tests/test_build_pipeline.sh"
python3 "$ROOT/tests/test_release.py"

find "$ROOT/luci-app-taoistfuchen/root" "$ROOT/tests" "$ROOT/scripts" -type f \( \
	-path '*/etc/init.d/*' -o \
	-path '*/etc/hotplug.d/*' -o \
	-path '*/etc/uci-defaults/*' -o \
	-path '*/usr/share/taoistfuchen/*.sh' -o \
	-path '*/www/cgi-bin/*' -o \
	-name '*.sh' \
	\) -print0 | xargs -0 -r -n1 sh -n

find "$ROOT/scripts" -type f -name '*.py' -print0 | \
	xargs -0 -r -n1 python3 -c 'import pathlib, sys; p = pathlib.Path(sys.argv[1]); compile(p.read_text(encoding="utf-8"), str(p), "exec")'

find "$ROOT/luci-app-taoistfuchen/htdocs" "$ROOT/luci-app-taoistfuchen/root/www" \
	-type f -name '*.js' -print0 | xargs -0 -r -n1 node --check

find "$ROOT/luci-app-taoistfuchen/root/usr/share" -type f -name '*.json' \
	-print0 | xargs -0 -r -n1 sh -c 'python3 -m json.tool "$1" >/dev/null' sh

echo "all tests: ok"
