# JSON implementations compared

Produced by run.sh on 2026-10-01 (AMD Ryzen 9 5900X 12-Core Processor, Linux x86-64, single thread; load average 17.21 at the start;
N=1 samples minimum, REPEATS=1 processes per cell, LIMIT=60 s). Pinned versions in fetch.sh and
the harness manifests; inputs from gen-inputs.py; check lines from reference.py. MB/s of input, higher is
better; peak RSS of the whole process (bin/maxrss); ns per document for the batch inputs. FAIL = rejected
valid input, crashed, or a check line that differs from reference.py's; DNF = past the time limit; n/a =
the implementation has no such mode. Warm steady state only (cold start is out of scope).

**Measured on a loaded machine (load average 17.21, FORCE=1): these figures are not comparable.**

Partial rerun on 2026-10-01 (ONLY='serde_json.*float_roundtrip|simdjson_nodejs', inputs: twitter twitterescaped citm_catalog canada github_events gsoc-2018 mesh numbers marine_ik tiny rest records strings integers floats events; tracks: dom typed stream query; load average 8.70 at
the start; N=1, REPEATS=1, LIMIT=60 s).

## DOM / untyped: JSON into the library's generic value tree

### DOM: MB/s

| input | yyjson | cJSON | json-c | Jansson | YAJL tree | simdjson DOM | RapidJSON | RapidJSON full-precision | RapidJSON in-situ | nlohmann/json | glaze generic | serde_json Value | serde_json Value float_roundtrip | sonic-rs Value | simd-json owned | simd-json borrowed | jiter JsonValue | encoding/json any | json/v2 any | sonic any | go-json any | jsoniter any | segmentio any | Jackson tree | fastjson2 JSONObject | Gson tree | DSL-JSON Object | JsonDocument | JsonNode | Newtonsoft JToken | json (Python) | orjson | msgspec | python-rapidjson | pysimdjson | JSON.parse (Node) | JSON.parse (Bun) | JSON.parse (Deno) | simdjson_nodejs | Cpanel::JSON::XS | JSON::XS | JSON::PP | lua-cjson (LuaJIT) | lua-cjson (Lua 5.5) | std.json Value | BJSON | StructuredData | EinScott/json |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C | C | C | C | C++ | C++ | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | C# | Python | Python | Python | Python | Python | JavaScript | JavaScript | JavaScript | JavaScript | Perl | Perl | Perl | Lua | Lua | Zig | Beef | Beef | Beef |
| twitter | 1015.8 | 389.5 | 121.4 | 66.8 | 170.5 | 3076.8 | 493.4 | 442.3 | 752.2 | 114.5 | 417.9 | 268.8 | 270.6 | 1061.8 | 342.9 | 484.8 | 684.7 | 86.8 | 142.5 | 287.9 | 527.6 | 166.6 | 46.7 | 475.6 | 551.1 | 231.8 | 382.4 | 493.4 | 232.5 | 138.6 | 152.6 | 552.6 | 433.4 | 193.5 | 339.8 | 466.1 | 595.3 | 501.2 | 96.4 | 258.1 | FAIL | 1.1 | 317.5 | 232.4 | 164.8 | 44.7 | FAIL | FAIL |
| twitterescaped | 924.6 | 285.9 | 95.1 | 55.1 | 146.0 | 1969.1 | 424.9 | 398.7 | 722.6 | 103.7 | 376.3 | 218.2 | 219.9 | 1332.2 | 271.4 | 453.3 | 328.5 | 75.7 | 121.8 | 286.9 | 366.5 | 96.9 | 72.8 | 326.2 | 519.5 | 159.8 | 468.0 | 630.6 | 256.4 | 121.7 | 204.6 | 447.3 | 341.4 | 197.1 | 272.2 | 352.7 | 380.5 | 419.3 | 118.4 | 251.6 | FAIL | 1.8 | 266.5 | 201.5 | 131.0 | 47.2 | FAIL | FAIL |
| citm_catalog | 1094.6 | 331.5 | 107.9 | 107.2 | 201.7 | 3170.2 | 826.6 | 648.3 | 1024.6 | 186.1 | 728.8 | 442.0 | 465.5 | 967.5 | 362.3 | 519.5 | 646.3 | 106.8 | 190.7 | 254.2 | 464.4 | 171.1 | 60.3 | 415.9 | 382.5 | 224.2 | 301.9 | 433.6 | 180.6 | 154.6 | 131.7 | 594.6 | 446.6 | 172.1 | 362.9 | 530.7 | 805.7 | 669.0 | 123.3 | 296.2 | 396.9 | 2.5 | 535.0 | 265.8 | 213.3 | 46.2 | 255.4 | 101.3 |
| canada | 902.1 | 72.3 | 26.2 | 32.5 | 69.1 | 1020.1 | FAIL | 224.6 | FAIL | 64.8 | 223.0 | FAIL | 154.7 | 892.4 | 341.4 | 315.3 | 271.0 | 39.9 | 84.2 | 193.9 | 179.7 | 41.3 | 42.5 | 175.3 | 137.8 | 127.6 | 315.3 | 270.7 | 112.1 | 40.4 | 55.5 | 210.8 | 229.6 | 56.5 | 192.7 | 329.0 | 260.0 | 316.1 | 88.5 | 116.7 | 131.7 | 1.8 | 103.8 | 61.9 | 94.9 | 41.5 | FAIL | FAIL |
| github_events | 2444.7 | 380.5 | 110.8 | 71.4 | 135.0 | 3349.4 | 583.1 | 571.5 | 948.5 | 115.0 | 475.8 | 303.2 | 304.3 | 1486.7 | 385.5 | 533.5 | 928.1 | 117.2 | 264.7 | 248.9 | 706.1 | 189.1 | 43.9 | 593.4 | 392.4 | 343.0 | 363.5 | 727.3 | 321.3 | 165.6 | 245.7 | 430.3 | 598.0 | 231.8 | 430.2 | 636.1 | 527.0 | 643.4 | 168.5 | 316.1 | 372.7 | 2.0 | 354.5 | 207.6 | 202.6 | 33.7 | 359.0 | 160.5 |
| gsoc-2018 | 1475.5 | 654.7 | 276.0 | 72.8 | 459.1 | 4053.8 | 482.7 | 483.2 | 914.3 | 135.5 | 1221.2 | 784.8 | 798.0 | 2388.5 | 815.1 | 936.2 | 1728.9 | 197.9 | 337.4 | 1453.8 | 1130.5 | 219.3 | 95.7 | 737.0 | 377.3 | 289.8 | 394.8 | 1174.3 | 516.7 | 232.8 | 441.8 | 695.1 | 930.5 | 385.4 | 671.4 | 868.0 | 822.5 | 1148.3 | 426.3 | 634.2 | 665.1 | 1.9 | 472.5 | 363.2 | 257.4 | 52.9 | 403.5 | 153.8 |
| mesh | 921.7 | 77.0 | 43.5 | 37.0 | 57.6 | 879.3 | 482.7 | 316.5 | 500.9 | 74.2 | 184.0 | 255.0 | 250.3 | 804.9 | 342.5 | 334.5 | 315.2 | 39.7 | 64.2 | 178.1 | 421.6 | 45.0 | 71.9 | 179.6 | 196.0 | 134.3 | 210.1 | 264.8 | 100.9 | 67.0 | 107.7 | 289.4 | 278.4 | 121.7 | 177.1 | 498.0 | 451.6 | 445.6 | 77.5 | 166.4 | FAIL | 1.9 | 136.8 | 133.9 | 68.0 | 42.7 | FAIL | FAIL |
| numbers | 1034.9 | 87.2 | 66.8 | 33.0 | 67.3 | 1076.2 | 324.7 | 331.3 | 560.6 | 73.2 | 246.7 | 432.8 | 403.1 | 747.0 | 280.9 | 323.8 | 684.7 | 50.5 | 79.5 | 201.4 | 513.2 | 63.9 | 97.6 | 288.4 | 220.3 | 195.6 | 416.6 | 310.6 | 212.5 | 70.9 | 141.1 | 478.8 | 506.3 | 158.6 | 448.9 | 533.8 | 546.4 | 501.2 | 64.7 | 146.7 | FAIL | 2.1 | 76.7 | 114.1 | 92.2 | 48.4 | FAIL | FAIL |
| marine_ik | 1069.4 | 100.1 | 33.3 | 40.3 | 62.5 | 960.0 | 438.3 | 332.3 | 471.8 | 83.9 | 201.3 | 242.3 | 232.6 | 656.7 | 282.2 | 292.6 | 340.4 | 37.8 | 75.1 | 216.0 | 320.8 | 75.9 | 42.5 | 237.4 | 327.0 | 136.9 | 280.7 | 144.1 | 42.7 | 40.0 | 101.7 | 229.6 | 239.8 | 115.2 | 186.7 | 395.0 | 427.3 | 283.9 | 64.7 | 117.1 | FAIL | 2.0 | 138.2 | 94.0 | 73.6 | 41.0 | FAIL | FAIL |
| tiny | 763.7 | 200.8 | 54.2 | 48.1 | 96.7 | 838.9 | 336.3 | 168.0 | 430.2 | 53.3 | 257.3 | 199.7 | 197.6 | 490.7 | 221.0 | 243.1 | 336.1 | 32.8 | 74.4 | 172.7 | 175.2 | 98.6 | 80.7 | 165.5 | 222.6 | 67.9 | 263.4 | 294.4 | 108.7 | 47.7 | 43.6 | 209.3 | 243.3 | 90.0 | 106.8 | 108.5 | 239.8 | 162.5 | 12.0 | 135.8 | FAIL | 1.6 | 67.2 | 94.7 | 96.5 | 36.9 | FAIL | FAIL |
| rest | 1571.1 | 197.8 | 101.7 | 53.4 | 123.2 | 1778.8 | 500.4 | 465.0 | 757.9 | 83.0 | 366.1 | 203.5 | 193.5 | 1469.8 | 328.2 | 477.0 | 475.1 | 57.5 | 124.8 | 299.3 | 297.2 | 141.5 | 50.3 | 373.1 | 449.0 | 96.0 | 217.7 | 612.3 | 46.8 | 102.4 | 98.0 | 290.1 | 212.6 | 127.9 | 228.6 | 315.1 | 372.4 | 352.9 | 61.7 | 209.9 | FAIL | 1.1 | 98.1 | 88.5 | 134.2 | 27.5 | FAIL | FAIL |
| records | 707.7 | 109.7 | 22.4 | 25.2 | 57.5 | 1039.7 | 252.7 | 226.8 | 272.2 | 35.3 | 99.9 | 45.5 | 75.0 | 365.2 | 113.4 | 250.9 | 107.1 | 22.1 | 44.0 | 74.6 | 114.5 | 51.0 | 23.9 | 150.3 | 246.8 | 95.7 | 195.6 | 182.2 | 52.1 | 15.6 | 40.1 | 75.3 | 76.9 | 52.4 | 48.1 | 137.9 | 134.8 | 98.9 | 57.5 | 47.5 | FAIL | 0.6 | 51.3 | 29.2 | 63.5 | 23.5 | FAIL | FAIL |
| strings | 642.4 | 303.2 | 151.2 | 44.4 | 204.9 | 1362.9 | 378.1 | 398.2 | 538.4 | 192.7 | 686.6 | 337.5 | 455.5 | 1035.7 | 492.5 | 636.6 | 265.0 | 87.3 | 185.5 | 568.1 | 280.2 | 167.0 | 62.1 | 350.8 | 399.7 | 156.0 | 230.4 | 475.4 | 293.4 | 228.9 | 140.2 | 365.8 | 263.1 | 161.8 | 448.3 | 216.5 | 272.9 | 281.8 | 200.8 | 435.4 | 486.0 | FAIL | 559.0 | 486.8 | 213.0 | 62.6 | 235.9 | FAIL |
| integers | 828.9 | 105.8 | 55.4 | FAIL | 46.3 | 629.4 | 331.3 | 246.4 | 380.3 | 85.4 | 211.4 | 179.3 | 177.8 | 628.5 | 269.0 | 276.4 | 248.3 | 42.2 | 68.9 | 158.5 | 249.0 | 103.1 | 68.6 | 165.0 | 176.8 | 120.7 | 110.5 | 190.1 | 133.6 | 57.2 | 96.0 | 168.8 | 153.3 | 86.7 | 151.6 | 252.4 | 192.4 | 243.3 | 66.8 | 188.6 | FAIL | 2.3 | FAIL | FAIL | 88.2 | 45.4 | FAIL | FAIL |
| floats | 387.1 | 82.6 | 49.8 | 36.7 | 65.8 | 272.0 | FAIL | 196.8 | FAIL | 65.5 | 287.3 | FAIL | 144.8 | 89.4 | 80.9 | 79.8 | 263.5 | 30.1 | 36.6 | 14.7 | 44.7 | 30.1 | 35.7 | 116.4 | 83.5 | 158.7 | 126.3 | 337.6 | 182.7 | 50.0 | 45.3 | 286.8 | 14.4 | 48.2 | 52.5 | 236.5 | 275.4 | 253.0 | 42.8 | 92.4 | FAIL | 2.3 | 104.5 | 95.7 | 58.1 | 48.0 | FAIL | FAIL |
| events | 1176.0 | 205.7 | 71.9 | 52.7 | 101.1 | 1265.6 | 405.5 | 386.6 | 598.8 | 79.1 | 298.0 | 176.6 | 180.3 | 895.3 | 227.5 | 288.4 | 365.9 | 43.0 | 93.8 | 188.9 | 198.9 | 102.9 | 71.4 | 237.2 | 230.9 | 125.7 | 354.1 | 339.2 | 139.8 | 67.5 | 77.2 | 243.9 | 295.2 | 113.8 | 150.6 | 178.3 | 319.8 | 240.6 | 37.1 | 147.7 | FAIL | 1.7 | 110.1 | 110.4 | 118.8 | 39.9 | FAIL | FAIL |

### DOM: peak RSS (MiB)

| input | yyjson | cJSON | json-c | Jansson | YAJL tree | simdjson DOM | RapidJSON | RapidJSON full-precision | RapidJSON in-situ | nlohmann/json | glaze generic | serde_json Value | serde_json Value float_roundtrip | sonic-rs Value | simd-json owned | simd-json borrowed | jiter JsonValue | encoding/json any | json/v2 any | sonic any | go-json any | jsoniter any | segmentio any | Jackson tree | fastjson2 JSONObject | Gson tree | DSL-JSON Object | JsonDocument | JsonNode | Newtonsoft JToken | json (Python) | orjson | msgspec | python-rapidjson | pysimdjson | JSON.parse (Node) | JSON.parse (Bun) | JSON.parse (Deno) | simdjson_nodejs | Cpanel::JSON::XS | JSON::XS | JSON::PP | lua-cjson (LuaJIT) | lua-cjson (Lua 5.5) | std.json Value | BJSON | StructuredData | EinScott/json |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C | C | C | C | C++ | C++ | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | C# | Python | Python | Python | Python | Python | JavaScript | JavaScript | JavaScript | JavaScript | Perl | Perl | Perl | Lua | Lua | Zig | Beef | Beef | Beef |
| twitter | 4.3 | 5.2 | 340.2 | 5.6 | 5.1 | 6.4 | 6.6 | 6.8 | 6.3 | 7.4 | 7.7 | 6.1 | 5.9 | 4.6 | 7.2 | 6.4 | 4.9 | 21.1 | 23.1 | 24.5 | 24.9 | 21.7 | 22.7 | 565.2 | 571.6 | 562.7 | 314.9 | 40.9 | 72.6 | 182.6 | 16.5 | 18.2 | 17.8 | 20.4 | 20.6 | 62.3 | 63.0 | 59.5 | 184.7 | 11.3 | FAIL | 13.1 | 7.1 | 5.9 | 4.3 | 6.7 | FAIL | FAIL |
| twitterescaped | 4.4 | 5.2 | 305.1 | 5.5 | 4.9 | 6.3 | 6.4 | 6.4 | 6.1 | 7.2 | 7.7 | 5.8 | 5.9 | 4.5 | 7.1 | 6.2 | 4.9 | 22.6 | 23.8 | 25.0 | 24.5 | 23.2 | 22.5 | 566.1 | 566.4 | 489.9 | 557.9 | 41.0 | 69.1 | 194.2 | 14.7 | 19.0 | 17.9 | 17.2 | 20.8 | 77.7 | 63.4 | 82.8 | 199.6 | 11.3 | FAIL | 11.9 | 7.0 | 6.0 | 4.2 | 6.4 | FAIL | FAIL |
| citm_catalog | 8.3 | 8.9 | 607.5 | 11.6 | 9.2 | 10.9 | 10.0 | 10.2 | 10.0 | 11.3 | 11.8 | 12.8 | 12.4 | 9.2 | 13.4 | 13.2 | 7.1 | 31.1 | 30.5 | 40.0 | 32.7 | 33.0 | 34.5 | 541.3 | 505.1 | 663.8 | 320.9 | 42.1 | 126.3 | 226.3 | 21.2 | 23.6 | 21.6 | 28.9 | 29.4 | 92.2 | 69.2 | 89.3 | 201.4 | 16.0 | 17.5 | 20.0 | 15.2 | 11.4 | 9.0 | 10.7 | 9.7 | 19.0 |
| canada | 13.0 | 19.4 | 150.6 | 17.1 | 20.0 | 12.9 | FAIL | 13.2 | FAIL | 14.3 | 16.3 | FAIL | 14.6 | 10.8 | 21.7 | 24.9 | 14.1 | 35.7 | 33.6 | 65.9 | 37.7 | 33.5 | 47.4 | 583.9 | 438.4 | 523.7 | 765.9 | 44.0 | 308.2 | 282.9 | 25.9 | 32.3 | 27.4 | 30.3 | 35.6 | 93.0 | 85.8 | 90.4 | 237.2 | 21.7 | 24.0 | 21.7 | 26.5 | 23.3 | 24.1 | 14.5 | FAIL | FAIL |
| github_events | 2.7 | 2.7 | 455.2 | 2.7 | 2.6 | 4.6 | 4.2 | 4.4 | 4.4 | 4.6 | 4.7 | 3.3 | 3.3 | 3.3 | 3.4 | 3.3 | 3.1 | 21.3 | 21.0 | 20.6 | 21.1 | 21.0 | 18.7 | 565.3 | 558.5 | 546.7 | 222.4 | 39.8 | 57.9 | 61.0 | 12.9 | 14.8 | 16.4 | 15.8 | 16.5 | 61.2 | 53.8 | 58.6 | 243.6 | 9.4 | 9.5 | 10.2 | 4.1 | 3.3 | 2.7 | 3.8 | 3.7 | 3.7 |
| gsoc-2018 | 12.3 | 13.6 | 312.2 | 14.3 | 13.3 | 14.9 | 17.1 | 17.1 | 14.2 | 16.0 | 15.7 | 12.1 | 12.2 | 10.2 | 20.3 | 14.6 | 9.4 | 35.3 | 33.6 | 47.9 | 41.8 | 34.3 | 33.9 | 678.4 | 681.8 | 705.5 | 265.8 | 49.3 | 129.0 | 245.9 | 24.0 | 30.3 | 24.2 | 29.8 | 35.2 | 129.5 | 101.8 | 122.8 | 524.9 | 17.3 | 20.5 | 17.9 | 18.8 | 16.0 | 9.6 | 14.9 | 15.7 | 16.8 |
| mesh | 5.4 | 9.3 | 76.0 | 7.0 | 10.2 | 9.0 | 8.0 | 8.0 | 7.9 | 8.7 | 11.3 | 6.5 | 6.3 | 7.8 | 11.0 | 9.7 | 6.3 | 26.2 | 24.6 | 31.1 | 26.7 | 24.9 | 25.5 | 535.5 | 521.2 | 682.6 | 563.6 | 39.5 | 93.5 | 134.7 | 17.0 | 21.8 | 19.7 | 20.2 | 24.2 | 97.9 | 58.0 | 96.7 | 167.9 | 12.4 | FAIL | 13.4 | 8.9 | 7.3 | 17.6 | 7.1 | FAIL | FAIL |
| numbers | 2.8 | 3.2 | 38.5 | 2.8 | 3.3 | 4.9 | 4.9 | 5.0 | 4.9 | 4.8 | 5.4 | 3.5 | 3.6 | 3.8 | 4.0 | 4.0 | 3.3 | 18.9 | 19.1 | 21.4 | 21.0 | 20.8 | 18.7 | 217.8 | 222.6 | 534.0 | 547.7 | 37.1 | 50.2 | 87.2 | 13.1 | 15.5 | 16.8 | 15.7 | 16.7 | 53.2 | 39.2 | 51.8 | 175.6 | 9.6 | FAIL | 10.2 | 11.0 | 3.4 | 5.0 | 3.7 | FAIL | FAIL |
| marine_ik | 16.7 | 30.6 | 215.7 | 25.3 | 32.8 | 18.2 | 19.1 | 18.9 | 19.0 | 22.7 | 30.5 | 24.4 | 26.2 | 18.1 | 32.9 | 31.1 | 22.6 | 52.0 | 45.8 | 67.0 | 53.6 | 49.7 | 51.0 | 600.7 | 676.7 | 898.8 | 684.9 | 51.1 | 426.2 | 399.9 | 29.0 | 38.3 | 30.1 | 34.5 | 43.5 | 139.5 | 110.6 | 131.3 | 241.1 | 26.6 | FAIL | 27.3 | 31.2 | 26.9 | 49.6 | 22.6 | FAIL | FAIL |
| tiny | 13.5 | 13.7 | 678.9 | 13.5 | 13.3 | 15.9 | 15.8 | 15.6 | 15.8 | 15.8 | 15.8 | 12.3 | 12.5 | 12.5 | 12.4 | 12.2 | 12.2 | 35.5 | 35.0 | 32.9 | 33.0 | 35.5 | 34.8 | 595.8 | 580.8 | 1639.9 | 576.5 | 127.4 | 125.2 | 123.2 | 22.4 | 24.2 | 25.9 | 24.5 | 25.3 | 74.3 | 92.2 | 76.2 | 278.4 | 21.7 | FAIL | 21.9 | 29.0 | 21.5 | 10.2 | 12.4 | FAIL | FAIL |
| rest | 10.5 | 10.3 | 628.5 | 10.3 | 10.1 | 12.7 | 12.4 | 12.4 | 12.4 | 12.4 | 12.9 | 11.1 | 11.4 | 11.1 | 11.4 | 11.5 | 11.2 | 29.5 | 28.4 | 27.4 | 29.9 | 27.8 | 27.5 | 594.3 | 504.4 | 587.7 | 559.9 | 60.9 | 129.5 | 128.7 | 20.8 | 22.6 | 24.3 | 22.7 | 23.8 | 71.4 | 95.7 | 72.3 | 467.1 | 17.1 | FAIL | 18.3 | 25.4 | 18.1 | 10.9 | 11.3 | FAIL | FAIL |
| records | 23.9 | 41.5 | 288.7 | 50.3 | 39.8 | 29.0 | 25.5 | 25.5 | 24.1 | 42.8 | 49.1 | 49.1 | 49.2 | 19.5 | 45.9 | 36.4 | 30.4 | 76.6 | 74.2 | 88.3 | 86.7 | 77.0 | 76.1 | 688.9 | 552.6 | 682.7 | 615.6 | 60.8 | 289.5 | 392.5 | 43.7 | 53.3 | 39.0 | 55.6 | 68.4 | 156.5 | 134.9 | 138.9 | 248.0 | 41.8 | FAIL | 50.9 | 56.0 | 46.4 | 53.9 | 41.9 | FAIL | FAIL |
| strings | 11.3 | 11.5 | 65.4 | 11.9 | 10.1 | 13.6 | 14.6 | 14.6 | 13.2 | 12.4 | 14.1 | 8.4 | 8.2 | 9.4 | 14.1 | 12.6 | 7.3 | 27.3 | 29.7 | 41.2 | 33.9 | 27.4 | 33.5 | 229.0 | 260.9 | 253.0 | 222.0 | 44.7 | 67.9 | 175.9 | 29.9 | 26.3 | 21.4 | 44.5 | 26.6 | 78.5 | 85.0 | 76.0 | 295.9 | 14.1 | 17.1 | FAIL | 15.1 | 10.4 | 6.4 | 11.6 | 15.1 | FAIL |
| integers | 16.0 | 27.3 | 166.5 | FAIL | 29.4 | 18.5 | 17.2 | 17.3 | 17.3 | 18.1 | 24.5 | 19.0 | 19.3 | 14.7 | 26.1 | 26.0 | 15.0 | 45.7 | 43.8 | 51.8 | 47.0 | 44.2 | 43.5 | 738.8 | 389.4 | 729.3 | 717.0 | 45.7 | 273.7 | 322.2 | 29.8 | 37.6 | 30.4 | 35.0 | 42.4 | 80.7 | 80.1 | 80.1 | 233.0 | 21.5 | FAIL | 22.1 | FAIL | FAIL | 38.4 | 16.7 | FAIL | FAIL |
| floats | 14.0 | 16.8 | 54.5 | 13.0 | 19.0 | 14.2 | FAIL | 14.9 | FAIL | 13.1 | 16.3 | FAIL | 10.8 | 12.6 | 18.8 | 19.0 | 9.8 | 31.3 | 31.4 | 39.6 | 33.5 | 31.6 | 31.1 | 291.0 | 690.6 | 586.3 | 543.7 | 40.6 | 181.2 | 183.7 | 23.2 | 30.1 | 23.7 | 28.5 | 30.0 | 76.4 | 57.5 | 74.0 | 154.2 | 15.7 | FAIL | 16.9 | 15.2 | 12.2 | 22.6 | 11.8 | FAIL | FAIL |
| events | 13.4 | 13.5 | 623.0 | 13.4 | 13.1 | 15.8 | 15.5 | 15.3 | 15.4 | 15.4 | 15.8 | 13.5 | 13.5 | 13.7 | 13.9 | 13.9 | 13.3 | 39.7 | 41.8 | 41.2 | 39.6 | 37.5 | 39.6 | 598.7 | 584.7 | 1633.9 | 577.4 | 79.4 | 92.4 | 91.2 | 23.5 | 25.4 | 26.8 | 25.4 | 26.4 | 75.5 | 117.5 | 76.7 | 974.1 | 20.6 | FAIL | 21.7 | 30.9 | 21.4 | 13.3 | 13.5 | FAIL | FAIL |

### DOM: ns per document (batch inputs)

| input | yyjson | cJSON | json-c | Jansson | YAJL tree | simdjson DOM | RapidJSON | RapidJSON full-precision | RapidJSON in-situ | nlohmann/json | glaze generic | serde_json Value | serde_json Value float_roundtrip | sonic-rs Value | simd-json owned | simd-json borrowed | jiter JsonValue | encoding/json any | json/v2 any | sonic any | go-json any | jsoniter any | segmentio any | Jackson tree | fastjson2 JSONObject | Gson tree | DSL-JSON Object | JsonDocument | JsonNode | Newtonsoft JToken | json (Python) | orjson | msgspec | python-rapidjson | pysimdjson | JSON.parse (Node) | JSON.parse (Bun) | JSON.parse (Deno) | simdjson_nodejs | Cpanel::JSON::XS | JSON::XS | JSON::PP | lua-cjson (LuaJIT) | lua-cjson (Lua 5.5) | std.json Value | BJSON | StructuredData | EinScott/json |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C | C | C | C | C++ | C++ | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | C# | Python | Python | Python | Python | Python | JavaScript | JavaScript | JavaScript | JavaScript | Perl | Perl | Perl | Lua | Lua | Zig | Beef | Beef | Beef |
| tiny | 141 | 538 | 1993 | 2245 | 1117 | 129 | 321 | 643 | 251 | 2025 | 420 | 541 | 547 | 220 | 489 | 444 | 321 | 3296 | 1452 | 625 | 617 | 1095 | 1338 | 652 | 485 | 1590 | 410 | 367 | 993 | 2266 | 2476 | 516 | 444 | 1200 | 1011 | 996 | 450 | 665 | 8970 | 795 | FAIL | 65947 | 1607 | 1141 | 1119 | 2928 | FAIL | FAIL |
| rest | 1292 | 10256 | 19947 | 37980 | 16463 | 1140 | 4055 | 4363 | 2677 | 24458 | 5542 | 9970 | 10485 | 1380 | 6182 | 4254 | 4271 | 35293 | 16261 | 6779 | 6827 | 14341 | 40367 | 5438 | 4519 | 21127 | 9319 | 3313 | 43324 | 19811 | 20697 | 6995 | 9545 | 15864 | 8877 | 6438 | 5448 | 5750 | 32862 | 9667 | FAIL | 1832865 | 20676 | 22938 | 15121 | 73716 | FAIL | FAIL |
| events | 318 | 1817 | 5199 | 7095 | 3698 | 295 | 922 | 967 | 624 | 4728 | 1254 | 2117 | 2073 | 417 | 1643 | 1296 | 1022 | 8691 | 3984 | 1979 | 1879 | 3633 | 5232 | 1576 | 1619 | 2974 | 1056 | 1102 | 2674 | 5539 | 4841 | 1532 | 1266 | 3284 | 2482 | 2097 | 1169 | 1554 | 10062 | 2530 | FAIL | 221264 | 3396 | 3384 | 3146 | 9368 | FAIL | FAIL |

## Typed: JSON into statically known structs

### Typed: MB/s

| input | glaze | serde_json | serde_json float_roundtrip | sonic-rs | simd-json | encoding/json | json/v2 | sonic | go-json | jsoniter | segmentio | Jackson databind | fastjson2 | DSL-JSON | Gson | System.Text.Json (source gen) | Newtonsoft.Json | msgspec Struct | pydantic | std.json | BJSON |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C++ | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | Python | Python | Zig | Beef |
| twitter | 918.8 | 437.3 | 449.6 | 591.1 | 453.6 | 238.2 | 288.4 | 319.9 | 783.5 | 317.3 | 175.5 | 325.2 | 765.3 | 488.0 | 229.8 | 352.1 | 217.9 | 449.7 | 185.8 | 268.6 | 45.6 |
| citm_catalog | 2099.5 | 847.4 | 789.0 | 924.1 | 627.7 | 219.9 | 417.8 | 887.8 | 617.6 | 476.8 | 544.6 | 597.3 | 795.7 | 403.2 | 436.5 | 354.5 | 235.7 | 508.9 | 146.9 | 446.3 | 50.3 |
| canada | 876.8 | FAIL | 351.7 | 572.6 | 516.1 | 124.5 | 137.8 | 441.3 | 372.8 | 103.2 | 193.1 | 272.7 | 211.6 | FAIL | 70.5 | 117.5 | 52.1 | 187.8 | 112.7 | 216.3 | n/a |

### Typed: peak RSS (MiB)

| input | glaze | serde_json | serde_json float_roundtrip | sonic-rs | simd-json | encoding/json | json/v2 | sonic | go-json | jsoniter | segmentio | Jackson databind | fastjson2 | DSL-JSON | Gson | System.Text.Json (source gen) | Newtonsoft.Json | msgspec Struct | pydantic | std.json | BJSON |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C++ | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | Python | Python | Zig | Beef |
| twitter | 6.7 | 4.9 | 5.1 | 5.4 | 6.7 | 21.2 | 21.2 | 32.6 | 23.1 | 20.7 | 20.3 | 241.4 | 294.6 | 238.5 | 226.7 | 63.9 | 75.1 | 18.1 | 32.5 | 2.7 | 7.3 |
| citm_catalog | 8.4 | 5.9 | 5.7 | 6.4 | 12.5 | 23.3 | 24.3 | 35.6 | 26.8 | 23.0 | 23.2 | 226.4 | 246.3 | 170.4 | 226.7 | 73.0 | 93.6 | 20.9 | 43.8 | 3.1 | 11.8 |
| canada | 10.0 | FAIL | 6.7 | 7.0 | 18.0 | 23.1 | 25.2 | 37.4 | 30.1 | 25.3 | 24.9 | 574.2 | 575.2 | FAIL | 557.8 | 191.6 | 162.4 | 27.8 | 59.0 | 4.3 | n/a |

## Streaming: every token, no tree

### Streaming: MB/s

| input | YAJL | simdjson On-Demand | RapidJSON SAX | RapidJSON SAX full-precision | nlohmann/json SAX | serde_json visitor | serde_json visitor float_roundtrip | jiter | encoding/json Token | jsontext | jsoniter Iterator | Jackson JsonParser | Gson JsonReader | fastjson2 JSONReader | Utf8JsonReader | Newtonsoft JsonTextReader | ijson | std.json Scanner | BJSON JsonReader |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Go | Go | Go | Java | Java | Java | C# | C# | Python | Zig | Beef |
| twitter | 391.4 | 1675.1 | 660.2 | 675.0 | 178.0 | 560.2 | 699.5 | 940.4 | 237.6 | 242.3 | 235.0 | 564.3 | 308.8 | 628.0 | 547.3 | 344.9 | 100.9 | 318.5 | 47.9 |
| twitterescaped | 396.9 | 1643.0 | 631.7 | 623.9 | 158.1 | 497.0 | 522.6 | 447.8 | 193.6 | 220.7 | 249.9 | 297.5 | 198.3 | 572.7 | 408.4 | 335.4 | 87.8 | 250.7 | 57.4 |
| citm_catalog | 385.3 | 2662.7 | 1076.3 | 956.0 | 250.7 | 903.5 | 902.5 | 1052.8 | 281.1 | 387.5 | 691.2 | 763.1 | 581.1 | 767.8 | 467.9 | 349.3 | 115.7 | 499.3 | 59.0 |
| canada | 121.2 | 825.2 | FAIL | 291.1 | 80.9 | FAIL | 376.5 | 403.2 | 139.8 | 176.0 | 108.6 | 312.3 | 100.6 | 105.9 | 175.7 | 88.9 | 42.3 | 244.8 | 50.0 |
| github_events | 604.2 | 2815.3 | 652.9 | 703.4 | 145.1 | 899.0 | 1065.2 | 1267.8 | 134.4 | 171.7 | 455.3 | 575.9 | 413.6 | 984.8 | 539.7 | 270.5 | 132.4 | 340.8 | 56.1 |
| gsoc-2018 | 850.3 | 3783.1 | 661.4 | 693.5 | 161.7 | 1659.3 | 1529.3 | 2417.7 | 350.1 | 405.1 | 283.9 | 893.3 | 338.3 | 476.7 | 897.1 | 624.2 | 320.1 | 347.4 | 56.7 |
| mesh | 128.5 | 737.1 | 654.6 | 458.9 | 92.5 | 525.0 | 531.8 | 401.0 | 89.8 | 150.8 | 147.1 | 230.9 | 125.8 | 243.2 | 156.2 | 99.1 | 38.7 | 205.1 | 40.1 |
| numbers | 130.3 | 923.5 | 752.6 | 452.8 | 82.0 | 680.3 | 645.6 | 540.9 | 137.8 | 185.6 | 123.9 | 321.1 | 98.0 | 225.5 | 170.1 | 95.4 | 52.9 | 279.6 | 50.2 |
| marine_ik | 129.6 | 802.4 | 661.7 | 516.8 | 110.9 | 515.9 | 522.3 | 393.7 | 111.7 | 165.3 | 316.9 | 270.3 | 179.3 | 384.2 | 210.9 | 85.1 | 37.3 | 211.4 | 47.1 |
| tiny | 193.5 | 691.0 | 385.3 | 452.2 | 102.0 | 361.9 | 405.4 | 395.8 | 73.8 | 72.2 | 264.5 | 208.5 | 66.5 | 337.3 | 273.6 | 95.3 | 12.4 | 187.4 | 47.7 |
| rest | 422.8 | 1444.9 | 522.7 | 532.6 | 134.7 | 553.7 | 642.8 | 602.6 | 130.7 | 165.6 | 250.7 | 441.5 | 208.5 | 564.4 | 514.9 | 223.7 | 57.4 | 275.5 | 54.0 |
| records | 272.4 | 1048.8 | 594.3 | 519.7 | 120.7 | 401.7 | 464.7 | 454.0 | 104.2 | 169.8 | 283.3 | 329.9 | 177.4 | 429.9 | 363.8 | 168.0 | 41.0 | 203.8 | 48.7 |
| strings | 299.9 | 1650.9 | 609.3 | 620.2 | 207.7 | 486.8 | 492.5 | 340.2 | 206.2 | 168.4 | 241.4 | 505.8 | 268.9 | 540.6 | 333.9 | 421.9 | 187.1 | 237.2 | 61.0 |
| integers | 142.3 | 459.0 | 459.9 | 333.6 | 109.8 | 435.3 | 420.5 | 378.6 | 106.0 | 137.0 | 312.7 | 219.5 | 157.2 | 200.1 | 146.2 | 115.8 | FAIL | 206.5 | 48.9 |
| floats | 104.7 | 223.5 | FAIL | 223.1 | 45.7 | FAIL | 213.1 | 307.1 | 40.4 | 44.3 | 39.1 | 122.7 | 75.2 | 57.7 | 98.6 | 66.3 | 62.5 | 73.2 | 50.9 |
| events | 252.7 | 962.4 | 518.2 | 530.7 | 97.5 | 418.1 | 497.4 | 509.5 | 91.5 | 105.4 | 274.9 | 210.9 | 100.5 | 425.9 | 335.9 | 167.6 | 28.4 | 222.4 | 51.2 |

### Streaming: peak RSS (MiB)

| input | YAJL | simdjson On-Demand | RapidJSON SAX | RapidJSON SAX full-precision | nlohmann/json SAX | serde_json visitor | serde_json visitor float_roundtrip | jiter | encoding/json Token | jsontext | jsoniter Iterator | Jackson JsonParser | Gson JsonReader | fastjson2 JSONReader | Utf8JsonReader | Newtonsoft JsonTextReader | ijson | std.json Scanner | BJSON JsonReader |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Go | Go | Go | Java | Java | Java | C# | C# | Python | Zig | Beef |
| twitter | 3.4 | 7.9 | 5.7 | 5.7 | 5.4 | 3.5 | 3.4 | 3.4 | 21.2 | 20.7 | 21.2 | 222.0 | 216.6 | 232.4 | 39.7 | 52.1 | 15.8 | 2.7 | 4.1 |
| twitterescaped | 3.2 | 5.9 | 5.5 | 5.5 | 5.1 | 3.6 | 3.5 | 3.4 | 18.9 | 18.9 | 21.3 | 220.8 | 223.9 | 229.2 | 40.4 | 52.1 | 15.3 | 22.6 | 3.9 |
| citm_catalog | 5.5 | 8.3 | 8.9 | 8.9 | 7.4 | 4.7 | 4.5 | 4.4 | 23.4 | 21.2 | 23.3 | 101.6 | 216.9 | 146.9 | 40.7 | 52.1 | 16.9 | 2.7 | 6.3 |
| canada | 6.4 | 11.1 | FAIL | 10.3 | 8.5 | FAIL | 5.0 | 5.2 | 23.4 | 20.6 | 24.9 | 95.9 | 217.3 | 587.8 | 38.4 | 53.5 | 17.4 | 3.2 | 7.3 |
| github_events | 2.7 | 4.8 | 4.4 | 4.4 | 4.2 | 3.1 | 3.1 | 2.9 | 19.0 | 21.0 | 19.5 | 198.7 | 211.8 | 550.6 | 40.0 | 51.7 | 15.3 | 31.6 | 3.2 |
| gsoc-2018 | 8.4 | 14.6 | 13.4 | 13.4 | 10.5 | 6.4 | 6.2 | 6.0 | 25.4 | 27.6 | 26.1 | 569.2 | 553.4 | 345.8 | 42.2 | 59.1 | 17.9 | 5.8 | 9.3 |
| mesh | 3.4 | 6.3 | 6.1 | 6.1 | 5.5 | 3.9 | 3.8 | 3.7 | 21.2 | 18.3 | 21.3 | 86.9 | 215.5 | 349.4 | 39.1 | 52.2 | 16.7 | 2.6 | 4.2 |
| numbers | 2.7 | 4.6 | 4.6 | 4.6 | 4.3 | 3.0 | 3.1 | 3.0 | 20.8 | 18.5 | 19.0 | 82.0 | 215.3 | 206.0 | 35.3 | 52.0 | 15.3 | 2.7 | 3.6 |
| marine_ik | 7.9 | 14.0 | 12.4 | 12.4 | 9.9 | 5.9 | 5.9 | 5.8 | 25.1 | 20.6 | 25.3 | 86.0 | 206.4 | 313.0 | 41.0 | 54.3 | 18.5 | 4.5 | 8.9 |
| tiny | 13.3 | 16.0 | 15.6 | 15.6 | 15.6 | 12.3 | 12.4 | 12.2 | 35.3 | 33.1 | 33.2 | 595.2 | 1604.2 | 586.3 | 50.7 | 123.4 | 24.5 | 10.2 | 12.2 |
| rest | 10.3 | 12.7 | 12.4 | 12.4 | 12.4 | 11.1 | 10.9 | 10.9 | 27.5 | 27.8 | 29.0 | 251.4 | 587.9 | 530.3 | 46.9 | 128.2 | 23.0 | 10.8 | 11.1 |
| records | 10.6 | 21.2 | 16.7 | 16.7 | 12.5 | 7.3 | 7.5 | 7.3 | 29.2 | 26.9 | 27.6 | 231.7 | 229.6 | 393.9 | 44.1 | 59.9 | 19.9 | 6.2 | 11.6 |
| strings | 8.2 | 13.6 | 13.0 | 13.1 | 10.3 | 6.0 | 6.3 | 5.7 | 26.2 | 25.4 | 25.6 | 163.7 | 230.5 | 191.8 | 41.7 | 65.2 | 17.5 | 33.5 | 9.1 |
| integers | 8.2 | 13.3 | 13.0 | 13.0 | 10.2 | 6.1 | 6.0 | 6.0 | 25.2 | 22.6 | 25.2 | 118.1 | 144.7 | 210.1 | 43.2 | 59.7 | FAIL | 4.8 | 9.1 |
| floats | 8.2 | 11.1 | FAIL | 13.0 | 10.2 | FAIL | 6.0 | 6.0 | 24.2 | 25.1 | 25.4 | 194.1 | 185.3 | 624.3 | 37.8 | 59.1 | 18.2 | 4.0 | 8.9 |
| events | 13.4 | 15.7 | 15.5 | 15.6 | 15.3 | 13.6 | 13.6 | 13.5 | 39.5 | 41.4 | 39.7 | 563.3 | 1592.4 | 584.4 | 51.4 | 90.8 | 25.6 | 13.3 | 13.3 |

### Streaming: ns per document (batch inputs)

| input | YAJL | simdjson On-Demand | RapidJSON SAX | RapidJSON SAX full-precision | nlohmann/json SAX | serde_json visitor | serde_json visitor float_roundtrip | jiter | encoding/json Token | jsontext | jsoniter Iterator | Jackson JsonParser | Gson JsonReader | fastjson2 JSONReader | Utf8JsonReader | Newtonsoft JsonTextReader | ijson | std.json Scanner | BJSON JsonReader |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Go | Go | Go | Java | Java | Java | C# | C# | Python | Zig | Beef |
| tiny | 558 | 156 | 280 | 239 | 1059 | 298 | 266 | 273 | 1463 | 1496 | 408 | 518 | 1623 | 320 | 395 | 1133 | 8724 | 577 | 2264 |
| rest | 4798 | 1404 | 3881 | 3809 | 15062 | 3664 | 3156 | 3367 | 15525 | 12252 | 8092 | 4595 | 9732 | 3595 | 3941 | 9068 | 35325 | 7365 | 37596 |
| events | 1479 | 388 | 721 | 704 | 3834 | 894 | 751 | 734 | 4084 | 3545 | 1360 | 1772 | 3718 | 878 | 1113 | 2230 | 13175 | 1681 | 7305 |

## On-demand: a few fields from a large document

### On-demand: MB/s

| input | simdjson On-Demand | glaze lazy_json | sonic-rs get | jiter | serde_json partial struct | serde_json partial float_roundtrip | gjson | jsonparser | sonic get | encoding/json partial struct | fastjson2 JSONPath | pysimdjson lazy | msgspec partial Struct |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C++ | C++ | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Java | Python | Python |
| twitter | 4523.7 | 778.9 | 845.1 | 1552.3 | 1275.4 | 1271.7 | 639.4 | 645.2 | 724.0 | 290.2 | 269.2 | 2321.4 | 1532.2 |
| citm_catalog | 4544.9 | 881.8 | 1237.0 | 1283.1 | 1460.6 | 1322.9 | 1293.6 | 1185.6 | 1357.4 | 419.5 | 347.5 | 2737.4 | 1178.9 |
| canada | 1552.2 | 497.1 | 217.7 | 745.0 | FAIL | 516.8 | 130.6 | 52.2 | 78.0 | 90.2 | 133.4 | 89.6 | 179.5 |

### On-demand: peak RSS (MiB)

| input | simdjson On-Demand | glaze lazy_json | sonic-rs get | jiter | serde_json partial struct | serde_json partial float_roundtrip | gjson | jsonparser | sonic get | encoding/json partial struct | fastjson2 JSONPath | pysimdjson lazy | msgspec partial Struct |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C++ | C++ | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Java | Python | Python |
| twitter | 5.6 | 5.7 | 3.6 | 3.4 | 3.5 | 3.7 | 22.4 | 20.6 | 21.0 | 21.1 | 564.4 | 17.5 | 16.8 |
| citm_catalog | 8.0 | 7.6 | 4.7 | 4.6 | 4.9 | 4.6 | 26.4 | 20.8 | 27.3 | 20.8 | 564.6 | 22.2 | 18.1 |
| canada | 11.1 | 8.7 | 5.4 | 5.2 | FAIL | 6.1 | 28.8 | 18.6 | 111.5 | 28.8 | 711.4 | 24.1 | 27.5 |

## Notes

Inputs (gen-inputs.py has the details and the origins): real-world files from simdjson's jsonexamples,
**twitter** 617 KB, **twitterescaped** 549 KB (all non-ASCII as \u escapes), **citm_catalog** 1.6 MB,
**canada** 2.1 MB (GeoJSON floats), **github_events** 64 KB, **gsoc-2018** 3.2 MB (long strings),
**mesh** 707 KB, **numbers** 147 KB, **marine_ik** 2.8 MB; generated, **tiny** 4.0 MB in 37,032
documents of 100-500 B, **rest** 4.0 MB in 1,972 documents of 1-10 KB, **events** 5.0 MB of NDJSON in
13,376 lines (those three are batches: one document per line, split before timing), **records** 4.3 MB
(one array of 10,000 objects), **strings** 3.0 MB (escapes, raw UTF-8, surrogate pairs), **integers**
3.0 MB (up to 2^64 - 1 and down to -2^63), **floats** 3.0 MB (long mantissas, halfway cases,
subnormals, the range's extremes). The typed and on-demand tracks use twitter, citm_catalog and canada.

Implementations (pinned in fetch.sh and the harness manifests; each harness's header comment says
exactly what its columns time):

- C (from source, -O3, generic x86-64): yyjson 0.13.0, cJSON 1.7.19, json-c 0.19, Jansson 2.15.1, YAJL
  2.1.0 (`YAJL tree` = yajl_tree; `YAJL` = its callback parser, numbers read as text and strtod'd).
- C++: simdjson 5.0.1 (`simdjson DOM` reuses one parser, its documented usage; `On-Demand` walks every
  value in the streaming track and reads only the queried fields in the on-demand track), RapidJSON
  master 24b5e7a (default flags; `full-precision` = kParseFullPrecisionFlag; `in-situ` copies the input
  into a reused buffer inside the timing first), nlohmann/json 3.12.0 (DOM and SAX), glaze 9.0.0
  (`generic` = glz::generic, numbers as double; typed via pure reflection; `lazy_json` on-demand).
- Rust 1.98.1: serde_json 1.0.151 (default features; `float_roundtrip` columns are a second build
  with that feature), sonic-rs 0.5.10, simd-json 0.18.1 (copies each document into a reused buffer
  inside the timing: it parses in place), jiter 0.17.0.
- Go 1.27.1: encoding/json, encoding/json/v2 and jsontext (standard library, no GOEXPERIMENT needed),
  bytedance/sonic 1.15.4, goccy/go-json 0.11.2, json-iterator 1.1.12, segmentio/encoding 0.5.4, gjson
  1.19.0, buger/jsonparser 1.6.1. `any` = Unmarshal into interface{} (numbers as float64);
  `partial struct` = structs holding only the queried fields. gjson, jsonparser and glaze lazy_json do
  not validate what they skip.
- Java (OpenJDK 27): Jackson 3.2.3, fastjson2 2.0.65 (floats as BigDecimal in its tree; JSONPath extract
  from the bytes), DSL-JSON 2.0.2 (typed through its annotation processor's generated converters),
  Gson 2.14.0 (its tree keeps numbers as text until read).
- C# (.NET 10.0.10): System.Text.Json (JsonDocument; JsonNode, whose children are materialized by a
  walk inside the timing because JsonNode.Parse creates them lazily; Utf8JsonReader; JsonSerializer
  with a source-generated context), Newtonsoft.Json 13.0.4 (DateParseHandling.None, otherwise date-like
  strings are rewritten; its readers decode UTF-8 inside the timing).
- Python 3.14: json, orjson 3.12.0, msgspec 0.22.0, python-rapidjson 1.25, pysimdjson 7.0.2 (`lazy` =
  Parser.parse proxies, a full simdjson tape converted only where read), ijson 3.5.1 (yajl2_c backend),
  pydantic 2.13.5 (model_validate_json, lax mode).
- JavaScript: JSON.parse on Node 26.10.0, Bun 1.4.2 and Deno 2.9.7 (the UTF-8 file is decoded to a
  string outside the timing); simdjson_nodejs 0.9.2 (Node, its parse into JavaScript objects; a 2022
  release over an old simdjson).
- Perl 5.42: Cpanel::JSON::XS 4.53, JSON::XS 4.04, JSON::PP 4.16 (the core one). Lua: lua-cjson 2.1.0.16
  on LuaJIT 2.1 and Lua 5.5.1. Zig 0.16.0: std.json (Value, typed parseFromSlice, Scanner).
- Beef (BeefBuild 0.43.6, Release): BJSON a1396c8 (tree, typed `[JsonObject]` classes, which build the
  tree first, and its JsonReader), Beef's own Beefy.utils.StructuredData, EinScott/json ab9ace5.

Why cells fail (every input is valid JSON; FAIL = rejected, crashed, or a check line that differs):

- Float conversion not correctly rounded by default (canada and floats, a last-bit difference in the
  number checksum): RapidJSON (all three default-flag columns; kParseFullPrecisionFlag fixes it),
  serde_json (without its float_roundtrip feature), DSL-JSON's typed path (canada), JSON::XS (most
  inputs with fractions; it also returns -9223372036854775808 as a string), EinScott/json (imprecise
  parser), StructuredData (fractions stored as 32-bit floats).
- Integers above INT64_MAX (integers): Jansson and ijson's yajl backend reject them; lua-cjson
  saturates them to INT64_MAX (strtoll).
- JSON::PP drops characters after some \u escape sequences (strings).
- StructuredData reads input as JSON only when it starts with `{`, or `[` followed by `{` or `"`, so it
  rejects top-level arrays of numbers. EinScott/json does not accept the `\/` escape (strings).
- n/a: BJSON's typed mapping cannot express canada's lists of lists of pairs.

Not included: Boost.JSON (needs the Boost headers, not installed, about 1 GB for the tree: over the
disk budget), DAW JSON Link (needs a hand-written mapping for each of the ~150 schema members),
zimdjson (targets Zig 0.14; does not compile with Zig 0.16: `@Type` is gone, ArrayList alignment
types changed), lua-rapidjson / lua-simdjson (not attempted), Zorbn/Json and Atma.Json (Beef: crash on
any \u escape / tokenizer only), RogueMacro json and JSON_Beef (Beef: do not build). Languages without
a toolchain here: Ruby, PHP, Swift, Dart, Nim, Crystal, Julia, R, Haskell, OCaml, Elixir/Erlang, D,
Kotlin, Scala.

Peak RSS is the whole process (runtime, the input, garbage the collector has not yet reclaimed), so
for the JVM and .NET it mostly reflects heap sizing. json-c 0.19's heap grows by about three times the
input per parse even though json_object_put reports the tree freed, so its RSS grows with the number
of runs.
