# Third-party notices

Mystral includes code and data adapted from the following projects.

## macmon

The AppleCLPC energy counter table and the IOReport channel description in
`Mystral/Services/IOReportPower.swift` (`CLPCEnergyChannels`) are ported from
[macmon](https://github.com/vladkens/macmon) (`src/clpc.rs`, `src/sources.rs`).

```
MIT License

Copyright (c) 2024 vladkens

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## exelban/stats

The M1 efficiency-cluster SMC keys (`Tp09`, `Tp0T`) in
`Mystral/Services/SensorRegistry.swift` come from
[Stats](https://github.com/exelban/stats) (`Modules/Sensors/values.swift`).
The prefix grouping of the other temperature keys was checked against Stats,
[macmon](https://github.com/vladkens/macmon), [mactop](https://github.com/metaspartan/mactop)
and [iSMC](https://github.com/dkorunic/iSMC), against load tests on an M3 Pro, and
against the load recordings in iSMC's repository for M1 through M6. iSMC is GPL-3.0:
its recordings were used to test Mystral's rules, and no table, description or
other text from it is included in Mystral.

```
MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
