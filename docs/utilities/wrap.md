# QEMU Wrapper (`wrap.sh`)

## Overview

`wrap.sh` is a utility designed to transparently execute x86_64 binaries on non-native architectures (or with specific QEMU configurations) by creating a compiled C++ wrapper.

## Key Features

- **Transparent Emulation**: Replaces the original binary with a wrapper that invokes QEMU.
- **Compiled Performance**: The wrapper is written in C++ and compiled with `g++ -O3` for minimal overhead.
- **Argument Forwarding**: Seamlessly passes all command-line arguments from the wrapper to the underlying emulated binary.

## Usage

### Syntax

```bash
./wrap.sh <path_to_executable>
```

### Process

1.  The original binary is renamed (e.g., `program` becomes `_program`).
2.  A C++ source file is generated, configured to call `/usr/bin/qemu-x86_64 -cpu max` on the renamed binary.
3.  The C++ source is compiled into a new binary with the original name.
4.  The temporary source file is removed.

## Requirements

- `g++`: For compiling the wrapper.
- `qemu-user-static` or `qemu-x86_64`: To provide the emulation layer.

## Technical Details

The wrapper uses the `execvp` system call to replace the wrapper process with the QEMU process, ensuring that process IDs and signals are handled correctly.
