[![ci](https://github.com/tillitis/tkey-device-signer/actions/workflows/ci.yaml/badge.svg?branch=main&event=push)](https://github.com/tillitis/tkey-device-signer/actions/workflows/ci.yaml)

# Tillitis TKey PQ-Signer

The TKey `pqsigner` device application is an ml-dsa-44 signing tool. It
can sign messages up to 4 kByte. It is, for instance, used by the
[tkey-sign-pq](https://github.com/tillitis/tkey-sign-cli-pq) for doing
digital signatures of files.

The `pqsigner` is using signing by the use of external MU instead of computing
it on the tkey to make it possible to sign larger files, use less RAM and to
optimize the signing speed while still using MLDSA-pure instead of Hash-MLDSA
for security considerations. The signing is done with the default "hedged"-signing
over "deterministic"-signing and implements a good DRBG to achieve this.

The library mldsa-native is used to add mldsa support and it has tests according to
NIST, KAT and ACVP test framework that can be used to test the algorithm.

Tests to run and stresstest the mldsa signing on protocol level and to use to test
a tkey is also added.

See [MLDSA Draft](https://www.ietf.org/archive/id/draft-connolly-cfrg-ml-dsa-security-considerations-01.html) for more information about hedged vs deterministic signing and external MU computation.

See [Release notes](RELEASE.md).

## Client Go package

We provide a Go package to use with `pqsigner`:

- https://github.com/tillitis/tkeysign-pq [![Go Reference](https://pkg.go.dev/badge/github.com/tillitis/tkeysign.svg)](https://pkg.go.dev/github.com/tillitis/tkeysign-pq)

## Signer application protocol

`pqsigner` has a simple application protocol on top of the [TKey Framing
Protocol](https://dev.tillitis.se/protocol/#framing-protocol).

The protocol state machine handling this protocol is documented in
[the implementation notes](docs/implementation-notes.md).

The protocol has the following requests and responses:

| *command*               | *Function*                       | *FP length* | *code* | *data*            | *response*              |
|-------------------------|----------------------------------|-------------|--------|-------------------|-------------------------|
| `CMD_GET_PUBKEY`        | Get the public key               | 1 B         | 0x01   | none              | `RSP_GET_PUBKEY`        |
| `CMD_SET_SIZE`          | Set size of message to be signed | 32 B        | 0x03   | size as 32 bit LE | `RSP_SET_SIZE`          |
| `CMD_LOAD_DATA`         | Load a chunk of message          | 128 B       | 0x05   | 127 B null-padded | `RSP_LOAD_DATA`         |
| `CMD_GET_SIG`           | Sign and get signature           | 1 B         | 0x07   | none              | `RSP_GET_SIG`           |
| `CMD_GET_NAMEVERSION`   | Identify version of app          | 1 B         | 0x09   | none              | `RSP_GET_NAMEVERSION`   |
| `CMD_GET_FIRMWARE_HASH` | Ask for digest of firmware       | 32 B        | 0x0b   | size as 32 bit LE | `RSP_GET_FIRMWARE_HASH` |

| *response*              | *FP length* | *code* | *data*                             |
|-------------------------|-------------|--------|------------------------------------|
| `RSP_GET_PUBKEY`        | 128 B       | 0x02   | 1312 byte mldsa44 public key       |
| `RSP_SET_SIZE`          | 4 B         | 0x04   | 1 byte status                      |
| `RSP_LOAD_DATA`         | 4 B         | 0x06   | 1 byte status                      |
| `RSP_GET_SIG`           | 128 B       | 0x08   | 2420 byte signature                |
| `RSP_GET_NAMEVERSION`   | 32 B        | 0x0a   | 2 * 4 byte name, version 32 bit LE |
| `RSP_GET_FIRMWARE_HASH` | 128 B       | 0x0c   | 1 byte status + 64 bytes digest    |

| *status replies* | *code* |
|------------------|--------|
| OK               | 0      |
| BAD              | 1      |

It identifies itself with:

- `name0`: "tk1  "
- `name1`: "pqsn"

Please note that `pqsigner` also replies with a `NOK` Framing Protocol
response status if the endpoint field in the FP header is meant for
the firmware (endpoint = `DST_FW`). This is recommended for
well-behaved device applications so the client side can probe for the
firmware.

Typical use by a client application:

1. Probe for firmware by sending firmware's `GET_NAME_VERSION` with FP
   header endpoint = `DST_FW`.
2. If firmware is found, load `pqsigner`.
3. Upon receiving the device app digest back from firmware, switch to
   start talking the `pqsigner` protocol above.
4. Send `CMD_GET_PUBKEY` to receive the `pqsigner`'s public key. If the
   public key is already stored, check against it so it's the expected
   key.
5. Send `CMD_SET_SIZE` to set the size of the message to sign.
6. Send repeated messages with `CMD_LOAD_DATA` to send the
   entire message.
7. Send `CMD_GET_SIG` to get the signature over the message.

**Please note**: The firmware detection mechanism is not by any means
secure. If in doubt a user should always remove the TKey and insert it
again before doing any operation.

## Licenses and SPDX tags

Unless otherwise noted, the project sources are copyright Tillitis AB,
licensed under the terms and conditions of the "BSD-2-Clause" license.
See [LICENSE](LICENSE) for the full license text.

Until Oct 17, 2024, the license was GPL-2.0 Only.

External source code we have imported are isolated in their own
directories. They may be released under other licenses. This is noted
with a similar `LICENSE` file in every directory containing imported
sources.

The project uses single-line references to Unique License Identifiers
as defined by the Linux Foundation's [SPDX project](https://spdx.org/)
on its own source files, but not necessarily imported files. The line
in each individual source file identifies the license applicable to
that file.

The current set of valid, predefined SPDX identifiers can be found on
the SPDX License List at:

https://spdx.org/licenses/

We attempt to follow the [REUSE
specification](https://reuse.software/).

## Building

You have two options for build tools: either you use our OCI image
`ghcr.io/tillitis/tkey-builder` or native tools.

An easy way to build is to use the provided scripts:

- `build.sh` for native tools.
- `build-podman.sh` for use with Podman.

These scripts automatically clone the [tkey-libs device
libraries](https://github.com/tillitis/tkey-libs) in a directory next
to this one.

If you want to use a pre-built libraries, download the libraries tar
ball from

https://github.com/tillitis/tkey-libs/releases

unpack it, and specify where you unpacked it in `LIBDIR` when
building:

```
make LIBDIR=~/Downloads/tkey-libs-v0.1.2
```

Note that your `lld` might complain if they were built with a
different version. If so, either use the same version the release used
or use podman.

### Building with Podman

On Ubuntu 22.10, running

```
apt install podman rootlesskit slirp4netns
```

should be enough to get you a working Podman setup.

You can then either:

- Use `build-podman.sh` as described above, which clones and builds
  the tkey-libs libraries as well.

- Download [pre-built versions of the tkey-libs
  libraries](https://github.com/tillitis/tkey-libs/releases) and
  define `LIBDIR` to where you unpacked the tkey-libs, something
  like:

  ```
  make LIBDIR=$HOME/Downloads/tkey-libs-v0.1.2 podman
  ```

  Note that `~` expansion doesn't work.

### Building with host tools

To build with native tools you need at least the `clang`, `llvm`,
`lld`, packages installed. Version 15 or later of LLVM/Clang is for
support of our architecture (RV32\_Zmmul). Ubuntu 22.10 (Kinetic) is
known to have this. Please see
[toolchain_setup.md](https://github.com/tillitis/tillitis-key1/blob/main/doc/toolchain_setup.md)
(in the tillitis-key1 repository) for detailed information on the
currently supported build and development environment.

Build everything:

```
$ make
```

If you cloned `tkey-libs` to somewhere else then the default set
`LIBDIR` to the path of the directory.

If your available `objcopy` is anything other than the default
`llvm-objcopy`, then define `OBJCOPY` to whatever they're called on
your system.

### Disabling touch requirement

The `signer` normally requires the TKey to be physically touched for
signing to complete. For special purposes it can be compiled with this
requirement removed by setting the environment variable
`TKEY_SIGNER_APP_NO_TOUCH` to some value when building. Example:

```
$ make TKEY_SIGNER_APP_NO_TOUCH=yesplease
```

Of course this changes the signer app binary and as a consequence the
derived private key and identity will change.

## Running

If you just want to sign a file or experiment with the signer, use the
[tkey-sign-pq](https://github.com/tillitis/tkey-sign-cli-pq) command which
you can also use as an example on how to load and run the signer
device app.

Please see the [Developer Handbook](https://dev.tillitis.se/) for [how
to run with QEMU](https://dev.tillitis.se/tools/#qemu-emulator) or
[how to run apps on a
TKey](https://dev.tillitis.se/devapp/#running-tkey-apps).

## Testing

The mldsa-native library used for mldsa implements a testing framework for mldsa.

To run KAT tests and ACVP tests

```
$ cd mldsa-native
$ make kat
$ make acvp
```

Tests for the tkey has also been implemented which tests tampering of signature
and tkey functionality of mldsa. It will require that `tkey-sign-pq` is installed
or can be set by the `--bin` argument of the scripts. 

```
$ make test-hw-mldsa
$ make test-hw-mldsa-protocol-negative
```