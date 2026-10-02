# JSON implementations compared

Produced by run.sh on 2026-10-02 (AMD Ryzen 9 5900X 12-Core Processor, Linux x86-64, single thread; load average 6.80 at the start;
N=5 samples minimum, REPEATS=3 settled processes per cell out of at most MAX_RUNS=9,
LIMIT=60 s). Pinned versions in fetch.sh and
the harness manifests; inputs from gen-inputs.py; check lines from reference.py. MB/s of input, higher is
better; peak RSS of the whole process (bin/maxrss); ns per document for the batch inputs. FAIL = rejected
valid input, crashed, or a check line that differs from reference.py's; DNF = past the time limit; n/a =
the implementation has no such mode; `~` = the cell never settled (run.sh's step 3): noise, not a figure to
trust. Warm steady state only (cold start is out of scope).

Partial rerun on 2026-10-02 (ONLY='lua-cjson \(LuaJIT\)|JsonNode|Newtonsoft JToken|JSON::PP', inputs: citm_catalog records events; tracks: dom; load average 4.34 at
the start; N=5, REPEATS=3, MAX_RUNS=9, LIMIT=60 s).

Partial rerun on 2026-10-02 (ONLY='JsonBeef.*', inputs: twitter twitterescaped citm_catalog canada github_events gsoc-2018 mesh numbers marine_ik tiny rest records strings integers floats events; tracks: dom typed stream query; load average 7.09 at
the start; N=5, REPEATS=3, MAX_RUNS=9, LIMIT=60 s).

## DOM / untyped: JSON into the library's generic value tree

### DOM: MB/s

| input | yyjson | cJSON | json-c | Jansson | YAJL tree | simdjson DOM | RapidJSON | RapidJSON full-precision | RapidJSON in-situ | nlohmann/json | glaze generic | serde_json Value | serde_json Value float_roundtrip | sonic-rs Value | simd-json owned | simd-json borrowed | jiter JsonValue | encoding/json any | json/v2 any | sonic any | go-json any | jsoniter any | segmentio any | Jackson tree | fastjson2 JSONObject | Gson tree | DSL-JSON Object | JsonDocument | JsonNode | Newtonsoft JToken | json (Python) | orjson | msgspec | python-rapidjson | pysimdjson | JSON.parse (Node) | JSON.parse (Bun) | JSON.parse (Deno) | simdjson_nodejs | Cpanel::JSON::XS | JSON::XS | JSON::PP | lua-cjson (LuaJIT) | lua-cjson (Lua 5.5) | std.json Value | JsonBeef | BJSON | StructuredData | EinScott/json |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C | C | C | C | C++ | C++ | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | C# | Python | Python | Python | Python | Python | JavaScript | JavaScript | JavaScript | JavaScript | Perl | Perl | Perl | Lua | Lua | Zig | Beef | Beef | Beef | Beef |
| twitter | 1027.3 | 382.9 | 118.0 | 71.4 | 174.4 | 3046.2 | 490.5 | 456.2 | 778.1 | 118.9 | 416.2 | 270.4 | 268.1 | 1064.6 | 356.3 | 502.7 | 652.9 | 78.3 | 145.8 | 279.8 | 386.4 | 132.3 | 40.9 | 427.3 | 537.7 | 236.5 | 342.4 | 638.2 | 251.7 | 146.7 | 167.6 | 557.8 | 438.6 | 112.8 | 212.3 | 462.4 | 431.3 | 488.8 | 94.6 | 243.3 | FAIL | 0.8 | 277.1 | 236.7 | 122.5 | 1309.3 | 45.6 | FAIL | FAIL |
| twitterescaped | 1636.5 | 172.8 | 41.0 | 37.2 | 156.5 | 1946.5 | 416.8 | 412.5 | 685.0 | 98.7 | 236.8 | 204.8 | 215.6 | 1315.2 | 179.4 | 380.5 | 229.6 | 63.9 | 111.5 | 254.1 | 290.1 | 78.9 | 62.1 | 460.5 | 514.9 | 152.6 | 372.9 | 626.9 | 230.2 | 143.9 | 200.0 | 476.3 | 337.2 | 209.0 | 275.6 | 361.2 | 392.4 | 430.8 | 125.8 | 257.3 | FAIL | 1.9 | 285.5 | 218.9 | 137.6 | 1023.6 | 48.3 | FAIL | FAIL |
| citm_catalog | 1124.2 | 327.6 | 130.4 | 110.0 | 203.0 | 3238.7 | 827.6 | 705.3 | 1033.8 | 195.9 | 749.2 | 457.3 | 453.2 | 1411.6 | 439.2 | 501.4 | 619.2 | 97.3 | 224.2 | 344.3 | 424.2 | 211.7 | 79.1 | 686.2 | 678.3 | 432.2 | 313.1 | 469.4 | 190.7 | 162.8 | 189.5 | 608.5 | 447.3 | 196.5 | 430.2 | 571.3 | 878.3 | 668.5 | 133.5 | 312.5 | 387.1 | 2.8 | 507.8 | 295.9 | 246.5 | 1637.4 | 53.3 | 291.5 | 172.8 |
| canada | 928.0 | 82.0 | 33.6 | 33.6 | 73.4 | 1004.5 | FAIL | 241.1 | FAIL | 69.2 | 318.3 | FAIL | 158.8 | 893.4 | 328.4 | 308.7 | 322.4 | 46.7 | 92.3 | 162.1 | 199.0 | 51.7 | 47.4 | 245.6 | 211.0 | 164.8 | 311.0 | 261.8 | 115.0 | 65.4 | 43.9 | 249.2 | 255.4 | 45.8 | 235.6 | 331.8 | 483.1 | 317.2 | 87.4 | 125.1 | 223.6 | 2.2 | 100.7 | 82.6 | 105.3 | 485.1 | 44.9 | FAIL | FAIL |
| github_events | 2270.1 | 391.2 | 161.8 | 71.5 | 221.4 | 3329.5 | 585.0 | 572.7 | 945.1 | 114.8 | 527.9 | 304.5 | 296.5 | 1479.6 | 398.8 | 576.6 | 866.4 | 127.4 | 196.6 | 476.6 | 507.3 | 244.1 | 61.6 | 553.1 | 769.1 | 330.9 | 391.4 | 726.5 | 255.4 | 166.1 | 252.0 | 692.5 | 613.6 | 231.4 | 487.6 | 683.8 | 522.5 | 659.9 | 159.8 | 310.7 | 359.3 | 2.0 | 363.6 | 255.4 | 183.7 | 1634.6 | 48.7 | 398.2 | 221.8 |
| gsoc-2018 | 1308.8 | 675.2 | 367.0 | 72.8 | 481.2 | 4022.3 | 470.8 | 484.5 | 938.2 | 136.6 | 1260.8 | 779.0 | 788.9 | 2359.2 | 690.4 | 951.9 | 1688.7 | 209.7 | 337.0 | 1028.0 | 926.2 | 198.0 | 101.0 | 925.1 | 413.1 | 294.1 | 392.7 | 1194.2 | 590.5 | 384.6 | 444.4 | 771.0 | 983.9 | 431.4 | 732.4 | 1028.6 | 812.0 | 1207.9 | 441.9 | 632.7 | 688.5 | 1.9 | 508.1 | 397.0 | 260.1 | 2555.3 | 55.8 | 441.7 | 198.4 |
| mesh | 916.8 | 79.2 | 46.0 | 36.7 | 57.6 | 881.6 | 489.3 | 346.7 | 513.0 | 74.5 | 179.9 | 245.9 | 243.6 | 885.6 | 339.2 | 333.5 | 296.3 | 35.9 | 66.4 | 163.8 | 324.5 | 59.2 | 74.4 | 180.6 | 229.5 | 149.1 | 317.1 | 260.6 | 106.3 | 68.3 | 106.4 | 285.1 | 274.7 | 122.5 | 238.2 | 513.3 | 464.8 | 463.6 | 77.4 | 164.5 | FAIL | 2.0 | 142.6 | 134.4 | 74.5 | 601.6 | 41.6 | FAIL | FAIL |
| numbers | 1046.6 | 86.8 | 66.8 | 33.2 | 72.4 | 1075.2 | 545.9 | 386.2 | 579.1 | 76.1 | 247.4 | 443.3 | 438.4 | 742.5 | 328.0 | 323.6 | 687.0 | 59.1 | 94.2 | 292.9 | 464.2 | 60.6 | 98.4 | 290.4 | 221.6 | 216.8 | 394.9 | 311.8 | 214.1 | 72.4 | 142.9 | 488.4 | 487.7 | 166.2 | 443.2 | 544.2 | 576.6 | 489.9 | 109.4 | 146.4 | FAIL | 2.1 | 127.5 | 130.5 | 93.9 | 808.9 | 48.9 | FAIL | FAIL |
| marine_ik | 1144.4 | 105.8 | 34.3 | 42.5 | 63.4 | 975.4 | 455.8 | 346.2 | 479.1 | 82.3 | 215.3 | 255.8 | 255.3 | 738.7 | 296.9 | 303.6 | 352.6 | 37.3 | 67.7 | 170.4 | 263.4 | 80.4 | 42.7 | 241.4 | 333.6 | 167.6 | 274.8 | 174.6 | 93.3 | 41.4 | 106.4 | 225.0 | 240.0 | 118.1 | 204.7 | 403.3 | 437.1 | 394.4 | 71.3 | 132.6 | FAIL | 2.1 | 128.0 | 107.5 | 89.7 | 627.8 | 40.4 | FAIL | FAIL |
| tiny | 984.7 | 205.2 | 53.6 | 47.4 | 96.5 | 861.9 | 336.0 | 301.5 | 439.5 | 71.4 | 270.9 | 200.6 | 203.5 | 537.3 | 213.5 | 248.4 | 316.8 | 35.2 | 72.3 | 151.7 | 152.9 | 82.9 | 77.3 | 176.9 | 255.9 | 72.4 | 289.4 | 320.7 | 122.3 | 49.2 | 42.9 | 205.4 | 249.5 | 92.2 | 110.6 | 152.3 | 267.7 | 178.0 | 21.3 | 135.1 | FAIL | 1.7 | 91.8 | 97.5 | 103.4 | 482.0 | 36.6 | FAIL | FAIL |
| rest | 1571.8 | 206.2 | 104.6 | 53.3 | 126.5 | 1815.8 | 508.6 | 470.1 | 779.1 | 82.4 | 347.2 | 202.9 | 202.6 | 1435.8 | 335.3 | 539.8 | 506.7 | 59.7 | 113.9 | 259.5 | 298.1 | 131.4 | 57.2 | 383.3 | 471.0 | 200.7 | 410.9 | 718.0 | 230.4 | 101.6 | 127.2 | 376.5 | 402.5 | 148.0 | 235.1 | 316.9 | 422.5 | 365.1 | 67.3 | 215.8 | FAIL | 1.8 | 159.9 | 147.3 | 168.0 | 1049.3 | 42.7 | FAIL | FAIL |
| records | 1114.1 | 172.7 | 44.4 | 40.4 | 89.7 | 1390.0 | 339.0 | 317.0 | 465.9 | 68.2 | 153.7 | 78.4 | 76.8 | 602.8 | 161.1 | 369.9 | 244.6 | 36.7 | 66.9 | 115.6 | 185.6 | 73.0 | 40.0 | 255.1 | 335.4 | 163.5 | 315.9 | 324.8 | 96.8~ | 29.0~ | 60.2 | 91.1 | 121.6 | 61.2 | 68.1 | 234.2 | 215.4 | 278.8 | 49.3 | 83.6 | FAIL | 0.9~ | 113.8 | 88.4 | 98.2 | 731.4 | 33.9 | FAIL | FAIL |
| strings | 944.7 | 400.8 | 250.6 | 66.3 | 273.4 | 1749.7 | 534.9 | 538.0 | 735.0 | 194.6 | 739.9 | 448.0 | 429.7 | 1063.7 | 469.8 | 703.6 | 306.9 | 133.3 | 212.1 | 846.5 | 405.2 | 156.4 | 59.4 | 384.8 | 436.7 | 243.4 | 362.4 | 663.6 | 370.0 | 334.2 | 156.0 | 392.4 | 262.3 | 185.2 | 507.7 | 293.6 | 309.8 | 322.5 | 193.4 | 487.9 | 455.8 | FAIL | 574.4 | 526.0 | 223.4 | 828.0 | 61.2 | 259.2 | FAIL |
| integers | 853.6 | 109.4 | 58.1 | FAIL | 63.0 | 628.3 | 368.5 | 260.2 | 382.6 | 90.0 | 231.5 | 182.0 | 177.9 | 633.9 | 275.4 | 271.5 | 263.3 | 40.7 | 73.2 | 188.1 | 202.8 | 100.6 | 62.4 | 177.8 | 179.2 | 124.7 | 159.4 | 196.4 | 128.0 | 61.4 | 102.2 | 171.4 | 165.9 | 92.3 | 155.3 | 274.1 | 235.3 | 228.0 | 84.0 | 196.1 | FAIL | 2.4 | FAIL | FAIL | 87.0 | 528.9 | 44.5 | FAIL | FAIL |
| floats | 389.2 | 84.3 | 52.2 | 36.6 | 66.3 | 269.7 | FAIL | 205.7 | FAIL | 65.1 | 284.7 | FAIL | 168.0 | 90.5 | 81.7 | 81.1 | 271.5 | 31.3 | 38.1 | 15.1 | 46.1 | 31.9 | 34.5 | 119.0 | 85.5 | 167.7 | 129.9 | 337.2 | 145.8 | 54.3 | 42.8 | 296.0 | 14.8 | 42.3 | 54.9 | 233.7 | 285.6 | 250.4 | 115.7 | 100.9 | FAIL | 2.3 | 102.7 | 97.5 | 58.7 | 263.3 | 48.3 | FAIL | FAIL |
| events | 1296.1 | 215.2 | 77.4 | 53.6 | 103.4 | 1262.0 | 405.7 | 371.0 | 611.1 | 82.0 | 299.9 | 180.2 | 181.9 | 945.6 | 238.0 | 330.9 | 372.0 | 43.2 | 88.4 | 167.8 | 209.6 | 94.0 | 71.3 | 255.2 | 364.4 | 147.3 | 362.9 | 434.9 | 151.1 | 73.6 | 82.8 | 253.7 | 297.4 | 124.4 | 152.4 | 200.0 | 339.1 | 240.5 | 39.1 | 163.2 | FAIL | 1.8~ | 108.6 | 114.4 | 121.3 | 730.7 | 39.8 | FAIL | FAIL |

### DOM: peak RSS (MiB)

| input | yyjson | cJSON | json-c | Jansson | YAJL tree | simdjson DOM | RapidJSON | RapidJSON full-precision | RapidJSON in-situ | nlohmann/json | glaze generic | serde_json Value | serde_json Value float_roundtrip | sonic-rs Value | simd-json owned | simd-json borrowed | jiter JsonValue | encoding/json any | json/v2 any | sonic any | go-json any | jsoniter any | segmentio any | Jackson tree | fastjson2 JSONObject | Gson tree | DSL-JSON Object | JsonDocument | JsonNode | Newtonsoft JToken | json (Python) | orjson | msgspec | python-rapidjson | pysimdjson | JSON.parse (Node) | JSON.parse (Bun) | JSON.parse (Deno) | simdjson_nodejs | Cpanel::JSON::XS | JSON::XS | JSON::PP | lua-cjson (LuaJIT) | lua-cjson (Lua 5.5) | std.json Value | JsonBeef | BJSON | StructuredData | EinScott/json |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C | C | C | C | C++ | C++ | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | C# | Python | Python | Python | Python | Python | JavaScript | JavaScript | JavaScript | JavaScript | Perl | Perl | Perl | Lua | Lua | Zig | Beef | Beef | Beef | Beef |
| twitter | 4.3 | 5.2 | 343.7 | 5.6 | 5.1 | 6.3 | 6.5 | 6.5 | 6.2 | 7.3 | 7.8 | 6.0 | 5.9 | 4.7 | 7.3 | 6.4 | 4.9 | 22.9 | 23.1 | 24.7 | 25.3 | 23.3 | 22.6 | 539.0 | 566.4 | 562.8 | 231.7 | 41.5 | 73.4 | 203.0 | 16.2 | 18.4 | 17.6 | 20.2 | 20.6 | 62.6 | 64.2 | 60.3 | 176.3 | 10.9 | FAIL | 12.8 | 6.9 | 6.0 | 4.4 | 9.1 | 7.0 | FAIL | FAIL |
| twitterescaped | 4.4 | 5.2 | 152.9 | 5.4 | 4.9 | 6.1 | 6.4 | 6.5 | 6.0 | 7.4 | 7.6 | 5.9 | 5.9 | 4.5 | 7.2 | 6.3 | 4.9 | 22.1 | 23.6 | 23.6 | 23.7 | 22.5 | 23.3 | 566.2 | 568.5 | 527.1 | 557.4 | 41.9 | 68.5 | 193.8 | 14.5 | 18.9 | 17.5 | 17.2 | 20.6 | 86.4 | 61.2 | 84.1 | 215.9 | 11.1 | FAIL | 11.6 | 7.0 | 5.8 | 4.2 | 8.6 | 6.9 | FAIL | FAIL |
| citm_catalog | 8.0 | 9.2 | 792.7 | 11.6 | 9.2 | 10.7 | 10.2 | 10.0 | 10.0 | 11.3 | 11.7 | 12.8 | 12.8 | 7.4 | 14.2 | 13.4 | 7.1 | 31.2 | 32.0 | 41.5 | 35.1 | 31.2 | 33.8 | 594.8 | 707.7 | 705.1 | 333.5 | 42.6 | 126.4 | 247.9 | 20.7 | 23.3 | 21.2 | 28.4 | 28.9 | 91.9 | 72.9 | 90.6 | 228.2 | 15.6 | 17.3 | 19.6 | 15.3 | 11.5 | 9.0 | 17.5 | 11.2 | 9.8 | 19.2 |
| canada | 12.6 | 19.2 | 218.2 | 17.1 | 20.0 | 12.9 | FAIL | 13.3 | FAIL | 14.4 | 16.4 | FAIL | 15.0 | 10.9 | 22.2 | 22.6 | 14.2 | 35.6 | 33.5 | 64.7 | 38.1 | 33.4 | 47.8 | 677.8 | 518.5 | 668.2 | 768.4 | 44.6 | 307.6 | 345.7 | 25.6 | 32.7 | 27.0 | 29.8 | 35.0 | 94.7 | 97.5 | 93.3 | 254.5 | 21.3 | 23.6 | 22.1 | 26.9 | 23.4 | 24.1 | 20.3 | 14.8 | FAIL | FAIL |
| github_events | 2.4 | 2.6 | 463.6 | 2.5 | 2.5 | 4.6 | 4.4 | 4.4 | 4.4 | 4.4 | 4.7 | 3.4 | 3.3 | 3.2 | 3.5 | 3.4 | 3.0 | 20.8 | 20.8 | 19.5 | 21.2 | 19.1 | 20.7 | 561.0 | 555.4 | 548.3 | 222.0 | 40.3 | 55.7 | 60.5 | 12.6 | 14.6 | 16.2 | 15.2 | 16.0 | 61.4 | 54.7 | 60.7 | 247.0 | 9.0 | 9.1 | 9.8 | 4.2 | 3.2 | 2.5 | 4.0 | 3.9 | 3.8 | 3.9 |
| gsoc-2018 | 14.1 | 13.6 | 409.1 | 14.3 | 13.3 | 14.8 | 17.0 | 17.1 | 14.3 | 16.2 | 15.7 | 12.2 | 12.1 | 10.0 | 18.5 | 14.9 | 9.5 | 34.2 | 34.1 | 45.0 | 41.1 | 34.5 | 33.7 | 679.7 | 697.9 | 711.4 | 564.2 | 50.4 | 129.8 | 247.1 | 23.8 | 30.0 | 24.3 | 29.4 | 35.1 | 130.0 | 107.5 | 125.6 | 570.3 | 17.1 | 19.9 | 17.6 | 18.6 | 16.1 | 9.6 | 30.7 | 15.3 | 15.9 | 17.0 |
| mesh | 5.4 | 9.3 | 91.4 | 7.1 | 10.2 | 8.9 | 8.0 | 8.0 | 7.9 | 8.6 | 11.3 | 6.6 | 6.5 | 6.4 | 10.3 | 9.5 | 6.2 | 21.3 | 26.3 | 30.4 | 29.2 | 25.2 | 23.8 | 541.2 | 559.4 | 687.7 | 560.2 | 40.5 | 97.2 | 128.2 | 16.6 | 21.4 | 19.7 | 19.7 | 23.9 | 98.5 | 59.4 | 95.2 | 173.3 | 12.2 | FAIL | 12.8 | 9.0 | 7.2 | 17.7 | 8.9 | 7.6 | FAIL | FAIL |
| numbers | 2.6 | 3.3 | 40.5 | 2.8 | 3.3 | 4.8 | 4.8 | 4.8 | 4.8 | 4.7 | 5.4 | 3.4 | 3.3 | 3.6 | 3.8 | 3.9 | 3.4 | 19.1 | 20.1 | 20.9 | 20.6 | 18.9 | 20.8 | 218.2 | 221.4 | 543.9 | 547.2 | 38.0 | 50.9 | 84.8 | 13.0 | 15.1 | 16.4 | 15.5 | 16.6 | 53.8 | 39.2 | 52.4 | 181.0 | 9.2 | FAIL | 10.2 | 11.0 | 3.4 | 5.0 | 4.4 | 4.3 | FAIL | FAIL |
| marine_ik | 17.2 | 30.7 | 278.3 | 25.5 | 33.0 | 18.1 | 19.1 | 19.1 | 19.0 | 21.9 | 30.3 | 25.6 | 25.7 | 16.9 | 32.6 | 32.3 | 22.8 | 50.2 | 47.6 | 65.8 | 53.4 | 48.3 | 53.4 | 693.7 | 677.9 | 1064.7 | 682.0 | 51.1 | 426.6 | 607.8 | 29.2 | 38.2 | 29.9 | 34.0 | 42.7 | 138.5 | 103.6 | 136.6 | 257.8 | 26.2 | FAIL | 26.7 | 30.3 | 30.4 | 49.8 | 26.1 | 22.5 | FAIL | FAIL |
| tiny | 13.5 | 13.5 | 845.2 | 13.5 | 13.5 | 15.8 | 15.5 | 15.6 | 15.6 | 15.6 | 15.8 | 12.3 | 12.3 | 12.4 | 12.4 | 12.4 | 12.2 | 33.6 | 33.3 | 33.2 | 33.4 | 35.4 | 33.2 | 597.3 | 579.6 | 4742.7 | 575.7 | 127.6 | 125.6 | 124.1 | 22.1 | 23.9 | 25.7 | 24.2 | 24.9 | 74.4 | 92.8 | 76.8 | 2551.3 | 21.3 | FAIL | 22.1 | 29.2 | 21.3 | 10.2 | 12.8 | 12.8 | FAIL | FAIL |
| rest | 10.5 | 10.4 | 716.5 | 10.3 | 10.3 | 12.6 | 12.4 | 12.4 | 12.4 | 12.5 | 12.6 | 11.3 | 11.1 | 11.3 | 11.4 | 11.2 | 11.1 | 27.8 | 27.8 | 29.6 | 28.5 | 28.0 | 27.4 | 595.0 | 574.3 | 585.8 | 571.6 | 61.0 | 129.1 | 128.9 | 20.5 | 22.2 | 24.0 | 22.8 | 23.5 | 71.1 | 96.2 | 73.4 | 577.6 | 17.0 | FAIL | 17.8 | 25.4 | 17.9 | 10.9 | 11.5 | 11.7 | FAIL | FAIL |
| records | 25.0 | 41.5 | 582.4 | 50.3 | 39.9 | 29.0 | 25.4 | 25.4 | 24.1 | 43.1 | 48.6 | 49.1 | 49.1 | 19.4 | 47.5 | 36.6 | 30.4 | 75.6 | 78.7 | 89.6 | 85.0 | 78.9 | 80.2 | 829.5 | 854.2 | 920.5 | 682.3 | 61.5 | 323.8 | 831.6 | 43.5 | 52.8 | 38.9 | 55.3 | 68.8 | 155.7 | 136.5 | 140.8 | 265.2 | 41.6 | FAIL | 50.5 | 55.4 | 50.3 | 54.0 | 37.4 | 42.1 | FAIL | FAIL |
| strings | 11.4 | 11.4 | 99.6 | 11.9 | 10.1 | 13.5 | 14.6 | 14.6 | 13.3 | 12.4 | 14.0 | 8.4 | 8.3 | 9.4 | 14.2 | 12.6 | 7.3 | 28.1 | 30.3 | 44.0 | 35.4 | 29.4 | 32.6 | 230.9 | 271.1 | 280.2 | 244.6 | 45.3 | 68.2 | 175.4 | 33.5 | 25.3 | 21.2 | 44.8 | 26.4 | 79.5 | 86.6 | 80.4 | 291.9 | 13.9 | 16.8 | FAIL | 15.7 | 10.2 | 6.4 | 28.5 | 11.7 | 15.2 | FAIL |
| integers | 17.1 | 26.9 | 207.2 | FAIL | 29.2 | 18.5 | 17.2 | 17.3 | 17.3 | 18.1 | 24.6 | 19.1 | 19.1 | 17.1 | 25.6 | 25.8 | 15.0 | 45.7 | 42.1 | 51.7 | 45.1 | 43.1 | 43.3 | 732.7 | 433.5 | 713.3 | 719.3 | 46.6 | 274.3 | 322.6 | 29.5 | 38.1 | 30.2 | 34.7 | 41.3 | 81.7 | 80.3 | 80.6 | 265.7 | 21.7 | FAIL | 22.1 | FAIL | FAIL | 38.6 | 27.2 | 17.3 | FAIL | FAIL |
| floats | 14.8 | 16.8 | 63.2 | 13.1 | 18.5 | 14.2 | FAIL | 15.1 | FAIL | 13.1 | 16.1 | FAIL | 10.6 | 12.6 | 19.8 | 20.0 | 9.6 | 31.7 | 31.6 | 37.1 | 33.6 | 29.8 | 32.5 | 405.1 | 693.2 | 679.3 | 723.8 | 41.4 | 180.8 | 185.3 | 23.1 | 30.7 | 23.5 | 28.6 | 30.9 | 76.9 | 58.4 | 81.3 | 237.0 | 15.8 | FAIL | 16.5 | 15.2 | 12.2 | 22.9 | 27.3 | 12.1 | FAIL | FAIL |
| events | 13.6 | 13.5 | 802.7 | 13.4 | 13.4 | 15.7 | 15.4 | 15.4 | 15.5 | 15.5 | 15.7 | 13.3 | 13.5 | 13.7 | 13.7 | 14.0 | 13.3 | 39.7 | 39.5 | 41.1 | 39.5 | 39.8 | 39.6 | 598.3 | 586.2 | 1635.2 | 572.8 | 79.7 | 92.8 | 92.1 | 23.0 | 25.0 | 26.6 | 25.1 | 26.0 | 75.6 | 117.6 | 78.2 | 1334.2 | 20.2 | FAIL | 21.3 | 30.5 | 21.1 | 13.3 | 13.7 | 13.8 | FAIL | FAIL |

### DOM: ns per document (batch inputs)

| input | yyjson | cJSON | json-c | Jansson | YAJL tree | simdjson DOM | RapidJSON | RapidJSON full-precision | RapidJSON in-situ | nlohmann/json | glaze generic | serde_json Value | serde_json Value float_roundtrip | sonic-rs Value | simd-json owned | simd-json borrowed | jiter JsonValue | encoding/json any | json/v2 any | sonic any | go-json any | jsoniter any | segmentio any | Jackson tree | fastjson2 JSONObject | Gson tree | DSL-JSON Object | JsonDocument | JsonNode | Newtonsoft JToken | json (Python) | orjson | msgspec | python-rapidjson | pysimdjson | JSON.parse (Node) | JSON.parse (Bun) | JSON.parse (Deno) | simdjson_nodejs | Cpanel::JSON::XS | JSON::XS | JSON::PP | lua-cjson (LuaJIT) | lua-cjson (Lua 5.5) | std.json Value | JsonBeef | BJSON | StructuredData | EinScott/json |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C | C | C | C | C++ | C++ | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | C# | Python | Python | Python | Python | Python | JavaScript | JavaScript | JavaScript | JavaScript | Perl | Perl | Perl | Lua | Lua | Zig | Beef | Beef | Beef | Beef |
| tiny | 110 | 526 | 2015 | 2278 | 1119 | 125 | 321 | 358 | 246 | 1513 | 399 | 538 | 531 | 201 | 506 | 435 | 341 | 3073 | 1495 | 712 | 706 | 1303 | 1397 | 610 | 422 | 1493 | 373 | 337 | 883 | 2194 | 2519 | 526 | 433 | 1172 | 976 | 709 | 403 | 607 | 5067 | 800 | FAIL | 63669 | 1176 | 1107 | 1045 | 224 | 2949 | FAIL | FAIL |
| rest | 1291 | 9838 | 19398 | 38035 | 16034 | 1117 | 3989 | 4316 | 2604 | 24608 | 5844 | 9999 | 10014 | 1413 | 6050 | 3759 | 4004 | 33959 | 17812 | 7819 | 6807 | 15443 | 35469 | 5294 | 4307 | 10112 | 4938 | 2826 | 8804 | 19971 | 15944 | 5389 | 5040 | 13712 | 8628 | 6403 | 4802 | 5557 | 30157 | 9403 | FAIL | 1147317 | 12686 | 13775 | 12077 | 1934 | 47526 | FAIL | FAIL |
| events | 288 | 1737 | 4832 | 6975 | 3615 | 296 | 921 | 1007 | 612 | 4561 | 1246 | 2074 | 2055 | 395 | 1570 | 1130 | 1005 | 8649 | 4228 | 2227 | 1783 | 3977 | 5244 | 1464 | 1026 | 2538 | 1030 | 859 | 2473 | 5079 | 4514 | 1473 | 1257 | 3003 | 2452 | 1869 | 1102 | 1554 | 9548 | 2290 | FAIL | 212074~ | 3442 | 3267 | 3082 | 512 | 9380 | FAIL | FAIL |

## Typed: JSON into statically known structs

### Typed: MB/s

| input | glaze | serde_json | serde_json float_roundtrip | sonic-rs | simd-json | encoding/json | json/v2 | sonic | go-json | jsoniter | segmentio | Jackson databind | fastjson2 | DSL-JSON | Gson | System.Text.Json (source gen) | Newtonsoft.Json | msgspec Struct | pydantic | std.json | JsonBeef [JsonObject] | BJSON |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C++ | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | Python | Python | Zig | Beef | Beef |
| twitter | 910.5 | 489.8 | 483.0 | 583.3 | 509.9 | 193.3 | 254.2 | 685.9 | 689.0 | 273.3 | 190.8 | 422.8 | 739.8 | 485.3 | 226.3 | 367.8 | 221.2 | 565.9 | 191.6 | 275.1 | 545.0 | 46.9 |
| citm_catalog | 2103.6 | 847.5 | 824.5 | 955.3 | 719.5 | 250.8 | 326.8 | 791.5 | 929.3 | 384.4 | 534.5 | 629.3 | 945.4 | 413.2 | 467.0 | 358.5 | 263.5 | 506.8 | 159.1 | 468.3 | 731.1 | 51.7 |
| canada | 952.3 | FAIL | 371.6 | 580.7 | 604.4 | 105.8 | 111.9 | 446.2 | 377.7 | 95.1 | 219.9 | 217.0 | 220.5 | FAIL | 91.3 | 128.7 | 69.0 | 221.7 | 125.8 | 234.9 | 257.9 | n/a |

### Typed: peak RSS (MiB)

| input | glaze | serde_json | serde_json float_roundtrip | sonic-rs | simd-json | encoding/json | json/v2 | sonic | go-json | jsoniter | segmentio | Jackson databind | fastjson2 | DSL-JSON | Gson | System.Text.Json (source gen) | Newtonsoft.Json | msgspec Struct | pydantic | std.json | JsonBeef [JsonObject] | BJSON |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C++ | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Go | Go | Java | Java | Java | Java | C# | C# | Python | Python | Zig | Beef | Beef |
| twitter | 6.9 | 5.1 | 5.1 | 5.7 | 6.9 | 21.4 | 21.2 | 34.0 | 22.5 | 21.2 | 21.3 | 282.7 | 298.8 | 254.4 | 210.5 | 64.6 | 76.1 | 17.6 | 31.6 | 2.5 | 5.1 | 7.5 |
| citm_catalog | 8.5 | 5.7 | 5.9 | 6.2 | 11.9 | 23.4 | 23.4 | 35.6 | 26.5 | 23.4 | 23.3 | 235.0 | 262.8 | 199.3 | 226.2 | 73.5 | 94.4 | 20.7 | 42.1 | 3.2 | 7.6 | 12.1 |
| canada | 9.9 | FAIL | 6.7 | 6.9 | 17.9 | 24.2 | 25.4 | 35.0 | 29.8 | 25.4 | 25.1 | 585.6 | 574.1 | FAIL | 557.9 | 192.3 | 159.7 | 27.5 | 57.6 | 4.4 | 12.7 | n/a |

## Streaming: every token, no tree

### Streaming: MB/s

| input | YAJL | simdjson On-Demand | RapidJSON SAX | RapidJSON SAX full-precision | nlohmann/json SAX | serde_json visitor | serde_json visitor float_roundtrip | jiter | encoding/json Token | jsontext | jsoniter Iterator | Jackson JsonParser | Gson JsonReader | fastjson2 JSONReader | Utf8JsonReader | Newtonsoft JsonTextReader | ijson | std.json Scanner | JsonBeef JsonReader | BJSON JsonReader |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Go | Go | Go | Java | Java | Java | C# | C# | Python | Zig | Beef | Beef |
| twitter | 458.9 | 2491.3 | 657.2 | 691.7 | 185.3 | 669.7 | 685.6 | 939.9 | 177.5 | 215.3 | 337.5 | 577.8 | 313.4 | 675.0 | 570.1 | 351.4 | 105.5 | 349.9 | 853.1 | 54.3 |
| twitterescaped | 397.8 | 1671.3 | 638.7 | 627.4 | 153.8 | 543.1 | 547.0 | 468.8 | 148.7 | 175.9 | 215.7 | 565.5 | 200.3 | 567.0 | 432.8 | 330.5 | 89.5 | 254.1 | 684.1 | 55.2 |
| citm_catalog | 388.2 | 2710.7 | 1067.0 | 1041.5 | 281.3 | 966.0 | 928.2 | 1045.4 | 288.3 | 472.2 | 545.7 | 832.0 | 572.4 | 914.1 | 483.9 | 391.3 | 107.9 | 539.0 | 990.5 | 59.8 |
| canada | 135.3 | 838.9 | FAIL | 292.0 | 85.5 | FAIL | 372.8 | 547.1 | 142.1 | 180.9 | 88.9 | 228.9 | 110.8 | 102.4 | 180.3 | 98.7 | 44.2 | 253.2 | 361.0 | 52.5 |
| github_events | 574.0 | 2786.4 | 650.7 | 701.6 | 166.6 | 996.2 | 1044.2 | 1260.6 | 224.3 | 285.4 | 346.6 | 608.9 | 439.8 | 939.6 | 553.1 | 360.3 | 132.7 | 366.6 | 1070.9 | 57.7 |
| gsoc-2018 | 907.0 | 3829.1 | 679.1 | 670.4 | 163.0 | 1771.6 | 1818.9 | 2444.9 | 346.6 | 393.0 | 280.1 | 983.6 | 343.8 | 491.4 | 916.9 | 629.5 | 315.8 | 355.8 | 2238.1 | 61.4 |
| mesh | 128.3 | 738.5 | 676.2 | 459.7 | 93.7 | 549.5 | 531.2 | 405.4 | 92.0 | 157.6 | 128.4 | 263.3 | 127.0 | 240.7 | 156.5 | 103.6 | 39.5 | 216.4 | 338.6 | 46.7 |
| numbers | 141.1 | 922.4 | 754.0 | 459.1 | 82.9 | 647.1 | 655.3 | 538.8 | 108.0 | 185.1 | 124.3 | 313.8 | 112.6 | 222.3 | 167.8 | 92.5 | 53.4 | 287.4 | 522.5 | 51.6 |
| marine_ik | 139.2 | 811.0 | 667.1 | 524.1 | 114.7 | 531.8 | 515.8 | 407.5 | 104.0 | 175.2 | 347.8 | 291.8 | 177.5 | 386.8 | 191.7 | 120.6 | 38.2 | 215.3 | 377.8 | 45.9 |
| tiny | 196.0 | 702.1 | 486.9 | 455.2 | 106.5 | 416.4 | 419.8 | 404.1 | 62.5 | 63.8 | 263.2 | 215.5 | 90.0 | 340.3 | 265.7 | 98.8 | 12.8 | 192.8 | 338.3 | 47.7 |
| rest | 422.7 | 1454.9 | 558.4 | 575.8 | 134.6 | 634.6 | 647.7 | 710.4 | 123.8 | 132.4 | 327.3 | 451.1 | 236.6 | 598.4 | 566.5 | 250.8 | 62.9 | 280.2 | 692.1 | 52.9 |
| records | 288.6 | 1073.4 | 598.7 | 555.1 | 125.7 | 456.8 | 465.3 | 458.1 | 105.0 | 172.8 | 248.7 | 319.9 | 228.0 | 454.6 | 369.2 | 193.2 | 43.8 | 220.8 | 477.5 | 48.9 |
| strings | 301.8 | 1766.6 | 616.8 | 632.0 | 204.7 | 500.9 | 508.1 | 357.1 | 181.8 | 178.7 | 204.6 | 523.9 | 270.7 | 565.9 | 342.3 | 430.6 | 195.4 | 240.3 | 661.2 | 64.3 |
| integers | 144.0 | 464.0 | 468.1 | 339.3 | 115.2 | 443.9 | 424.6 | 386.3 | 101.5 | 140.3 | 306.4 | 224.3 | 162.4 | 214.7 | 148.3 | 121.0 | FAIL | 211.5 | 288.2 | 48.4 |
| floats | 106.3 | 261.4 | FAIL | 225.1 | 70.7 | FAIL | 221.9 | 336.1 | 42.6 | 44.8 | 37.7 | 127.6 | 87.0 | 69.6 | 101.6 | 68.5 | 65.1 | 74.6 | 236.0 | 50.8 |
| events | 301.6 | 1024.6 | 532.9 | 538.1 | 125.0 | 489.9 | 498.2 | 513.4 | 92.4 | 99.0 | 270.2 | 319.5 | 182.6 | 434.9 | 388.8 | 172.3 | 28.8 | 224.2 | 462.4 | 49.6 |

### Streaming: peak RSS (MiB)

| input | YAJL | simdjson On-Demand | RapidJSON SAX | RapidJSON SAX full-precision | nlohmann/json SAX | serde_json visitor | serde_json visitor float_roundtrip | jiter | encoding/json Token | jsontext | jsoniter Iterator | Jackson JsonParser | Gson JsonReader | fastjson2 JSONReader | Utf8JsonReader | Newtonsoft JsonTextReader | ijson | std.json Scanner | JsonBeef JsonReader | BJSON JsonReader |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Go | Go | Go | Java | Java | Java | C# | C# | Python | Zig | Beef | Beef |
| twitter | 3.4 | 6.0 | 5.7 | 5.6 | 5.3 | 3.4 | 3.5 | 3.4 | 19.2 | 18.9 | 20.9 | 190.4 | 217.6 | 233.5 | 40.5 | 52.5 | 15.3 | 2.3 | 4.5 | 4.5 |
| twitterescaped | 3.2 | 5.8 | 5.5 | 5.6 | 5.4 | 3.4 | 3.5 | 3.4 | 19.0 | 18.7 | 19.0 | 207.9 | 227.0 | 230.2 | 40.6 | 52.5 | 15.3 | 14.5 | 4.3 | 4.3 |
| citm_catalog | 5.5 | 10.2 | 8.9 | 8.9 | 7.4 | 4.7 | 4.7 | 4.5 | 22.5 | 22.8 | 23.4 | 104.9 | 218.2 | 146.4 | 40.8 | 52.5 | 16.6 | 2.7 | 6.5 | 6.5 |
| canada | 6.4 | 11.1 | FAIL | 10.3 | 8.4 | FAIL | 5.2 | 5.0 | 22.9 | 18.6 | 23.2 | 553.4 | 216.8 | 589.1 | 40.4 | 54.1 | 17.1 | 3.4 | 7.6 | 7.6 |
| github_events | 2.3 | 4.6 | 4.4 | 4.6 | 4.2 | 3.2 | 3.2 | 2.9 | 19.5 | 20.6 | 19.5 | 217.2 | 224.5 | 551.6 | 40.5 | 51.9 | 15.0 | 29.3 | 3.4 | 3.3 |
| gsoc-2018 | 8.4 | 14.6 | 13.4 | 13.4 | 10.4 | 6.2 | 6.2 | 6.0 | 25.6 | 25.4 | 25.9 | 562.5 | 555.0 | 561.7 | 43.3 | 58.4 | 17.6 | 8.1 | 9.6 | 9.6 |
| mesh | 3.4 | 6.1 | 6.1 | 6.1 | 5.5 | 3.8 | 3.7 | 3.6 | 21.1 | 18.5 | 19.1 | 87.2 | 217.1 | 208.5 | 39.5 | 52.5 | 16.5 | 2.5 | 4.6 | 4.6 |
| numbers | 2.5 | 4.9 | 4.6 | 4.6 | 4.4 | 3.0 | 3.1 | 3.0 | 20.5 | 20.6 | 20.9 | 82.2 | 215.9 | 222.4 | 35.5 | 51.9 | 15.1 | 2.5 | 3.6 | 3.6 |
| marine_ik | 7.8 | 13.8 | 12.4 | 12.4 | 9.9 | 5.9 | 5.9 | 5.8 | 25.1 | 20.9 | 25.0 | 90.1 | 223.7 | 348.7 | 43.1 | 54.6 | 18.7 | 4.0 | 8.9 | 8.9 |
| tiny | 13.5 | 15.8 | 15.6 | 15.5 | 15.5 | 12.2 | 12.3 | 12.4 | 35.4 | 33.3 | 33.3 | 592.1 | 1605.9 | 591.3 | 51.2 | 123.1 | 24.2 | 10.2 | 12.6 | 12.6 |
| rest | 10.3 | 12.7 | 12.3 | 12.4 | 12.4 | 10.9 | 11.0 | 10.8 | 28.4 | 28.1 | 27.8 | 247.5 | 585.3 | 464.1 | 47.4 | 127.9 | 22.6 | 10.8 | 11.3 | 11.1 |
| records | 10.6 | 21.1 | 16.7 | 16.6 | 12.6 | 7.4 | 7.4 | 7.1 | 28.0 | 27.3 | 27.5 | 220.6 | 561.5 | 453.2 | 44.5 | 60.5 | 19.6 | 5.8 | 11.9 | 11.8 |
| strings | 8.2 | 13.2 | 13.0 | 13.0 | 10.2 | 6.0 | 6.1 | 5.8 | 25.9 | 25.8 | 25.8 | 186.2 | 231.4 | 206.2 | 42.4 | 64.4 | 17.5 | 25.5 | 9.4 | 9.2 |
| integers | 8.2 | 13.3 | 13.1 | 13.0 | 10.3 | 6.0 | 6.0 | 5.9 | 25.3 | 22.5 | 25.2 | 119.8 | 128.7 | 188.7 | 43.8 | 60.5 | FAIL | 4.2 | 9.3 | 9.2 |
| floats | 7.9 | 11.1 | FAIL | 13.0 | 10.2 | FAIL | 5.8 | 5.9 | 25.1 | 25.1 | 25.2 | 178.8 | 210.8 | 474.9 | 38.2 | 59.0 | 17.9 | 4.9 | 9.2 | 9.4 |
| events | 13.4 | 15.6 | 15.4 | 15.4 | 15.4 | 13.5 | 13.5 | 13.5 | 39.7 | 39.4 | 39.8 | 592.1 | 1605.6 | 595.4 | 52.0 | 91.3 | 24.8 | 13.3 | 13.6 | 13.7 |

### Streaming: ns per document (batch inputs)

| input | YAJL | simdjson On-Demand | RapidJSON SAX | RapidJSON SAX full-precision | nlohmann/json SAX | serde_json visitor | serde_json visitor float_roundtrip | jiter | encoding/json Token | jsontext | jsoniter Iterator | Jackson JsonParser | Gson JsonReader | fastjson2 JSONReader | Utf8JsonReader | Newtonsoft JsonTextReader | ijson | std.json Scanner | JsonBeef JsonReader | BJSON JsonReader |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C | C++ | C++ | C++ | C++ | Rust | Rust | Rust | Go | Go | Go | Java | Java | Java | C# | C# | Python | Zig | Beef | Beef |
| tiny | 551 | 154 | 222 | 237 | 1015 | 259 | 257 | 267 | 1729 | 1694 | 411 | 501 | 1200 | 317 | 406 | 1093 | 8443 | 560 | 319 | 2266 |
| rest | 4800 | 1395 | 3633 | 3523 | 15069 | 3197 | 3133 | 2856 | 16388 | 15319 | 6200 | 4497 | 8576 | 3390 | 3582 | 8091 | 32270 | 7240 | 2932 | 38367 |
| events | 1239 | 365 | 701 | 695 | 2990 | 763 | 750 | 728 | 4043 | 3776 | 1383 | 1170 | 2047 | 860 | 961 | 2170 | 12983 | 1667 | 808 | 7539 |

## On-demand: a few fields from a large document

### On-demand: MB/s

| input | simdjson On-Demand | glaze lazy_json | sonic-rs get | jiter | serde_json partial struct | serde_json partial float_roundtrip | gjson | jsonparser | sonic get | encoding/json partial struct | fastjson2 JSONPath | pysimdjson lazy | msgspec partial Struct | JsonBeef JsonReader |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C++ | C++ | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Java | Python | Python | Beef |
| twitter | 4467.9 | 778.2 | 841.7 | 1519.3 | 1280.3 | 1281.0 | 397.1 | 644.5 | 487.4 | 304.6 | 278.6 | 2298.4 | 1571.3 | 941.0 |
| citm_catalog | 4439.2 | 884.2 | 1240.9 | 1508.8 | 1442.8 | 1358.1 | 1019.6 | 1199.6 | 992.5 | 527.0 | 688.7 | 2793.8 | 1208.1 | 1317.8 |
| canada | 1542.2 | 511.0 | 248.5 | 809.2 | FAIL | 529.9 | 155.7 | 91.9 | 86.5 | 81.8 | 146.5 | 85.9 | 218.3 | 385.2 |

### On-demand: peak RSS (MiB)

| input | simdjson On-Demand | glaze lazy_json | sonic-rs get | jiter | serde_json partial struct | serde_json partial float_roundtrip | gjson | jsonparser | sonic get | encoding/json partial struct | fastjson2 JSONPath | pysimdjson lazy | msgspec partial Struct | JsonBeef JsonReader |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| *language* | C++ | C++ | Rust | Rust | Rust | Rust | Go | Go | Go | Go | Java | Python | Python | Beef |
| twitter | 5.6 | 5.6 | 3.8 | 3.4 | 3.7 | 3.7 | 20.9 | 18.5 | 22.8 | 19.0 | 563.6 | 17.4 | 16.7 | 4.7 |
| citm_catalog | 8.0 | 7.6 | 4.7 | 4.5 | 4.7 | 4.8 | 26.9 | 20.7 | 27.8 | 20.6 | 572.5 | 22.2 | 17.6 | 6.7 |
| canada | 11.1 | 8.6 | 5.5 | 5.1 | FAIL | 6.1 | 28.7 | 20.7 | 111.0 | 26.6 | 721.0 | 23.8 | 27.2 | 7.7 |

Load average 4.68 at the end; 0 measured cells never settled (`~`).

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
- Beef (BeefBuild 0.43.6, Release): JsonBeef (this repository: JsonDocument; JsonReader, every token;
  typed `[JsonObject]` classes bound straight from the reader's tokens; on demand, JsonReader.Find and
  SkipValue, which checks what it skips, through to the end of the text), BJSON a1396c8 (tree, typed
  `[JsonObject]` classes, which build the tree first, and its JsonReader), Beef's own
  Beefy.utils.StructuredData, EinScott/json ab9ace5.

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
