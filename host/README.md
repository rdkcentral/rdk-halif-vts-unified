# VTS RAFT Host Flow

This folder mirrors the polaris host execution model so L1/L2/L3 tests can be run on the DUT through the same RAFT-based flow.

## 1. Prepare the RAFT environment

```bash
source python_venv/bin/activate
./install.sh
```

## 2. Build the binary and generated profiles

```bash
./build.sh TARGET=linux VARIANT=C
```

The generated runtime profile is placed under:

- build/bin/profiles/sink/unified_sink_hal_profile.yaml
- build/bin/run_hal_test.sh

## 3. Run L1/L2/L3 through RAFT

From the host folder:

```bash
source python_venv/bin/activate
python3 tests/TestCases/vts_all_tests.py --levels L1 L2 L3
```

or run only one level:

```bash
python3 tests/TestCases/vts_all_tests.py --levels L1
python3 tests/TestCases/vts_all_tests.py --levels L2
python3 tests/TestCases/vts_all_tests.py --levels L3
```

## Notes

- The rack config file is `tests/configs/vts_rack_config.yml`.
- The DUT device config file is `tests/configs/vts_deviceConfig.yml`.
- The actual L1/L2/L3 suite names in the YAML files should be replaced with the real suite names after the component inventory is finalized.
- The execution path remains aligned with the generated build outputs under `/build/bin` and not the repo-local `/profiles` directory.
