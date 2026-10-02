#!/bin/bash
# Fetches everything the comparison benchmark builds against into deps/ (git-ignored), each pinned so
# runs are comparable:
#   - git clones of the C, C++, Lua and Beef implementations, pinned to a commit (a release tag's commit
#     where the project tags releases);
#   - the Zig compiler, verified against its published checksum;
#   - Java jars from Maven Central, Perl distributions from CPAN, and the Bun and Deno runtimes, each
#     verified by sha256;
#   - the real-world JSON corpus gen-inputs.py copies into inputs/ (from simdjson's jsonexamples at the
#     pinned simdjson commit), verified by sha256.
# Libraries that come from a package registry are pinned where the language pins them: Cargo.lock
# (rust/), go.sum (go/), exact NuGet versions (cs/JsonBench.csproj), exact pip versions (build.sh
# python). Beef's built-in StructuredData is copied from the installed Beef.
set -euo pipefail
C="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$C/deps"
fetch() { # name url commit
	local dir="$C/deps/$1"
	if [ ! -d "$dir/.git" ]; then
		git init -q "$dir"
		git -C "$dir" remote add origin "$2"
	fi
	if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$3" ]; then
		git -C "$dir" fetch -q --depth 1 origin "$3"
		git -C "$dir" checkout -q --detach FETCH_HEAD
	fi
	echo "$1 $(git -C "$dir" rev-parse --short HEAD)"
}
# Pinned 2026-10-01 (the newest release, or the newest commit where there are no recent releases)
fetch yyjson        https://github.com/ibireme/yyjson.git         6447536015f3d600f3d65323b10976103b337ca7  # 0.13.0
fetch cJSON         https://github.com/DaveGamble/cJSON.git       c859b25da02955fef659d658b8f324b5cde87be3  # v1.7.19
fetch json-c        https://github.com/json-c/json-c.git          aa716cd8d663c976b99b0f30f102ee1d8ef63146  # json-c-0.19-20260627
fetch jansson       https://github.com/akheron/jansson.git        dbb5fb3636e155fccfce4cd215de752779bd6971  # v2.15.1
fetch yajl          https://github.com/lloyd/yajl.git             a0ecdde0c042b9256170f2f8890dd9451a4240aa  # 2.1.0
fetch simdjson      https://github.com/simdjson/simdjson.git      8c512a3227ad322bfcb43c57c71fac67a83b5b8e  # v5.0.1
fetch rapidjson     https://github.com/Tencent/rapidjson.git      24b5e7a8b27f42fa16b96fc70aade9106cf7102f  # master (1.1.0 is from 2016)
fetch nlohmann-json https://github.com/nlohmann/json.git          55f93686c01528224f448c19128836e7df245f72  # v3.12.0
fetch glaze         https://github.com/stephenberry/glaze.git     d78832c82289c61a9315bfbc35332cec9f4e93ca  # v9.0.0
fetch lua-cjson     https://github.com/openresty/lua-cjson.git    e6daf3cdfac61055af3f7d88d9886942ff0de6e6  # 2.1.0.16
fetch BJSON         https://github.com/M0n7y5/BJSON.git           a1396c8b6153f3e607091e7e9bf90799c3e655c0
fetch EinScott-json https://github.com/EinScott/json.git          ab9ace51325b48bd721b524a34eeb7207f2179d0  # newest commit (2024-04-06), no releases

# Beef's built-in JSON reader (Beefy.utils.StructuredData, which reads JSON and TOML) from the
# installed Beef, for the beef/ harness: StructuredData needs only DisposeProxy besides corlib
BEEF_UTILS="$(dirname "$(readlink -f "$(command -v beefbuild)")")/../BeefLibs/Beefy2D/src/utils"
mkdir -p "$C/beef/src/beefy"
cp "$BEEF_UTILS/StructuredData.bf" "$BEEF_UTILS/DisposeProxy.bf" "$C/beef/src/beefy/"
echo "StructuredData from $(readlink -f "$BEEF_UTILS") ($(beefbuild -version 2>&1 | head -1))"

# Zig itself, verified against the published checksum
ZIG_VERSION=0.16.0
ZIG_SHA256=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
if [ ! -x "$C/deps/zig/zig" ]; then
	tarball="$C/deps/zig-$ZIG_VERSION.tar.xz"
	curl -fsSL -o "$tarball" "https://ziglang.org/download/$ZIG_VERSION/zig-x86_64-linux-$ZIG_VERSION.tar.xz"
	echo "$ZIG_SHA256  $tarball" | sha256sum -c --quiet -
	mkdir -p "$C/deps/zig"
	tar -xJf "$tarball" -C "$C/deps/zig" --strip-components=1
	rm "$tarball"
fi
echo "zig $("$C/deps/zig/zig" version)"

download() { # file url sha256
	local target="$C/deps/$1"
	if [ ! -f "$target" ] || ! echo "$3  $target" | sha256sum -c --quiet - 2> /dev/null; then
		curl -fsSL -o "$target.part" "$2"
		echo "$3  $target.part" | sha256sum -c --quiet -
		mv "$target.part" "$target"
	fi
}

# Java libraries from Maven Central (the newest on 2026-10-01). The Java harness is compiled with javac
# against these jars: the installed Gradle does not run on the installed JDK 27.
mkdir -p "$C/deps/jars"
MAVEN=https://repo1.maven.org/maven2
while read -r path sha; do
	download "jars/${path##*/}" "$MAVEN/$path" "$sha"
done << 'LIST'
tools/jackson/core/jackson-core/3.2.3/jackson-core-3.2.3.jar a0c17e7e665a5e95c82f5fb45c0fec2ae3dc556c80f0016452c9c84cd23f3817
tools/jackson/core/jackson-databind/3.2.3/jackson-databind-3.2.3.jar 235b72436af983857e44efa42449f4f0a2c571e69d6c5d9dd1253ae7d192dcf2
com/fasterxml/jackson/core/jackson-annotations/2.22/jackson-annotations-2.22.jar 21ddb598807d3a51a876704eb979d9296e1c6a6f47ab1826ff88c6d6a127a2d0
com/alibaba/fastjson2/fastjson2/2.0.65/fastjson2-2.0.65.jar e12cd0e49047e052533d897d4b45d1074a21229f2a1939404234398d4c10c06d
com/dslplatform/dsl-json/2.0.2/dsl-json-2.0.2.jar 8b4d6aa6384b1d657ddb0811da1c2fc3568a26c8f6e950f4f4caa74e15eba0a5
com/google/code/gson/gson/2.14.0/gson-2.14.0.jar 2cbd119bf1961c28788310963dc80ba65f58cdeec1dd139c8bdb1240faa2c36f
LIST
echo "jars: $(ls "$C/deps/jars" | wc -l) verified"

# Perl distributions from CPAN (build.sh perl installs them into perl/local; JSON::PP is the one in
# the installed Perl)
mkdir -p "$C/deps/cpan"
CPAN=https://cpan.metacpan.org/authors/id
while read -r path sha; do
	download "cpan/${path##*/}" "$CPAN/$path" "$sha"
done << 'LIST'
R/RU/RURBAN/Cpanel-JSON-XS-4.53.tar.gz 32d7e099c9a71e5693f951b26114c89854de419f17ff7402ad5890fa41dbd819
M/ML/MLEHMANN/JSON-XS-4.04.tar.gz 8eff1e9f304c5625b59ab7b42258415f6d3e3681c1ddab6b725518a018a7f5e0
M/ML/MLEHMANN/common-sense-3.75.tar.gz a86a1c4ca4f3006d7479064425a09fa5b6689e57261fcb994fe67d061cba0e7e
M/ML/MLEHMANN/Types-Serialiser-1.01.tar.gz f8c7173b0914d0e3d957282077b366f0c8c70256715eaef3298ff32b92388a80
M/ML/MLEHMANN/Canary-Stability-2013.tar.gz a5c91c62cf95fcb868f60eab5c832908f6905221013fea2bce3ff57046d7b6ea
LIST
echo "cpan: $(ls "$C/deps/cpan" | wc -l) verified"

# Bun and Deno (single binaries; JSON.parse on their engines, JavaScriptCore and V8), checksums as
# published with the GitHub releases
runtime() { # name zip-url sha256
	if [ ! -x "$C/deps/$1/$1" ]; then
		download "$1.zip" "$2" "$3"
		mkdir -p "$C/deps/$1"
		unzip -q -j -o "$C/deps/$1.zip" -d "$C/deps/$1"
		rm "$C/deps/$1.zip"
	fi
	echo "$1 $("$C/deps/$1/$1" --version | head -1)"
}
runtime bun https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/bun-linux-x64.zip \
	36368faef7527875d5ffa52e53cd48021741f2a83eb6208a8dd64068d422a913
runtime deno https://github.com/denoland/deno/releases/download/v2.9.7/deno-x86_64-unknown-linux-gnu.zip \
	c6527f24f4b16031d3ae4fa9f658d5f11534c8d84ce7dc8502420280919c3490

# The real-world corpus: simdjson's jsonexamples (the simdjson-data commit simdjson v5.0.1 pins), see
# gen-inputs.py for what each file is and where it comes from
mkdir -p "$C/deps/corpus"
DATA=https://raw.githubusercontent.com/simdjson/simdjson-data/351949906abde446f0314bf79606fb5d884f5be7/jsonexamples
while read -r name sha; do
	download "corpus/$name" "$DATA/$name" "$sha"
done << 'LIST'
twitter.json 30721e496a8d73cfc50658923c34eb2c0fbe15ee6835005e43ee624d8dedf200
twitterescaped.json 2a288b5af4691c55b6f40fa534225b3e08b8d8b7f7ca4ed29bc5c7c81566ed4a
citm_catalog.json a73e7a883f6ea8de113dff59702975e60119b4b58d451d518a929f31c92e2059
canada.json f83b3b354030d5dd58740c68ac4fecef64cb730a0d12a90362a7f23077f50d78
github_events.json c9eebb2cf2d46649059e9d48700919bacb3e8e0fb58452065a1a9de7778fd22e
gsoc-2018.json 72f1ef4898d88049da856c2ab8f4ec3e2c968ce209b2bbfd16cef842eb2e185f
mesh.json 45bc8bf429340a874a7af8ea7056d60497402f80f55dba1e6ecc4ca8f1e46aff
numbers.json 82e9ddfe00963110ed8a0704e7df4d1ad1af9c0f336d1b24431ebc63cf430a2b
marine_ik.json 61590a397542ae274ccd8a47ba9f64e7c9216a223a5e7e702dea5b2375411d62
LIST
echo "corpus: $(ls "$C/deps/corpus" | wc -l) files verified"
