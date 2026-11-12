# Unified HALIF VTS Test Framework

## Table of Contents

- Acronyms, Terms and Abbreviations
- Description
- Repository Structure
- Prerequisites
- Build Instructions
- Running the Test Suite
- Runtime Profiles
- Supported Components
- Packaging
- L1/L2 Test Execution
- L3 Automation Execution
- Troubleshooting

---

# Acronyms, Terms and Abbreviations

| Acronym | Description |
|----------|-------------|
| HAL | Hardware Abstraction Layer |
| VTS | Verification Test Suite |
| UT | Unit Test |
| DUT | Device Under Test |
| L1 | Functional Tests |
| L2 | Module Functional Tests |
| L3 | Module Testing with External Stimulus |
| YAML | YAML Ain't Markup Language |
| RAFT | Rapid Automation Framework for Testing |

---

# Description

The Unified HALIF VTS Framework combines multiple RDK HALIF test repositories into a single executable test binary.

The framework automatically:

- Synchronizes repositories listed in `manifest.xml`
- Builds all HALIF test components into a single executable
- Registers component test suites automatically
- Collects runtime profile YAML files
- Generates unified runtime profile files
- Packages binaries and profiles into a deployable archive

The framework is designed to support both Linux host execution and ARM target execution using a common build flow.

---

# Repository Structure

```text
rdk-halif-vts-unified/
├── build.sh
├── Makefile
├── manifest.xml
├── src/
│   ├── unified_main.c
│   └── unified_testsuite_register.c
├── build/
├── ut-core/
└── vts_hal_test_components/
```

---

# Supported Components

The framework can integrate any HALIF repository listed in `manifest.xml`.

Example components:

- power_manager
- device_settings
- hdmi_cec
- deepsleep_manager
- rmf_audio_capture
- tvsettings

Additional repositories can be added through the manifest without modifying the build architecture.

---

# Prerequisites

## Linux Host

Required packages:

```bash
sudo apt update

sudo apt install -y \
    git \
    gcc \
    g++ \
    make \
    autoconf \
    automake \
    libtool \
    pkg-config \
    wget \
    tar
```

## ARM Build

Source the platform SDK before building.

Example:

```bash
source <sdk-environment-setup>
```

---

# Build Instructions

## Linux Build

```bash
./build.sh TARGET=linux
```

## ARM Build

```bash
./build.sh TARGET=arm
```

Build artifacts are generated under:

```text
build/
```

---

# Runtime Profiles

During build, profile YAML files are copied to:

```text
build/bin/profiles/
```

Standard component profiles:

```text
build/bin/profiles/sink/
build/bin/profiles/source/
```

Unified runtime profiles:

```text
build/bin/profiles/sink/unified_sink_hal_profile.yaml

build/bin/profiles/source/unified_source_hal_profile.yaml
```

### Special Handling

For rmf_audio_capture:

```text
rmfAudioCaptureAuxNotSupported.yaml

rmfAudioCaptureAuxSupported.yaml
```

are copied directly into:

```text
build/bin/profiles/
```

---

# Running the Test Suite

After build:

```bash
cd build/bin
```

### Run using Sink Profile

```bash
./run_hal_test.sh \
-p profiles/sink/unified_sink_hal_profile.yaml
```

### Run using Source Profile

```bash
./run_hal_test.sh \
-p profiles/source/unified_source_hal_profile.yaml
```

### Run Directly

```bash
./hal_test \
-p profiles/sink/unified_sink_hal_profile.yaml
```

---

# Packaging

The build automatically generates:

```text
build/vts_hal_unified.tar.gz
```

Contents:

```text
bin/
├── hal_test
├── run_hal_test.sh
├── profiles/
└── lib/
```

---

# L1/L2 Test Execution

Deploy package:

```bash
scp build/vts_hal_unified.tar.gz root@<DUT>:/tmp
```

On DUT:

```bash
cd /tmp

tar -xzf vts_hal_unified.tar.gz

cd bin
```

Run:

```bash
./run_hal_test.sh \
-p profiles/sink/unified_sink_hal_profile.yaml
```

---

# L3 Automation Execution

L3 automation is executed using RAFT.

Required configuration files:

```text
vts_rack_config.yml
vts_deviceConfig.yml
```

Example:

```bash
python vts_l1l2_test.py \
--config ../configs/vts_rack_config.yml \
--deviceConfig ../configs/vts_deviceConfig.yml
```

Ensure:

- DUT is reachable through SSH.
- HAL package is copied to DUT.
- Correct profile path is configured.
- Port 10022 is accessible if applicable.

---

# Troubleshooting

## Build Failure

Clean and rebuild:

```bash
./build.sh clean

./build.sh TARGET=linux
```

## Framework Cleanup

```bash
./build.sh dist_clean
```

## Verify Generated Profiles

```bash
find build/bin/profiles -name "*.yaml"

## Verify Runtime Includes

```bash
cat build/bin/profiles/sink/unified_sink_hal_profile.yaml
```

---

* Notes

- Component repositories are fetched from `manifest.xml`.
- Test registration is generated automatically
- New HALIF repositories can be added without changing the framework logic.
- Unified profiles use the existing UT-Core parser include mechanism.
- The *framework supports* both Linux and ARM targets.