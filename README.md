# dirless-connect

End-user CLI for [Dirless](https://dirless.com) — obtain short-lived SSH certificates without managing `authorized_keys`.

## Install

Download the latest static binary for your architecture from [Releases](https://github.com/dirless/dirless-connect/releases) and place it in your `PATH`:

```sh
# Linux x86_64
curl -Lo /usr/local/bin/dirless-connect \
  https://github.com/dirless/dirless-connect/releases/latest/download/dirless-connect-x86_64
chmod +x /usr/local/bin/dirless-connect

# Linux aarch64
curl -Lo /usr/local/bin/dirless-connect \
  https://github.com/dirless/dirless-connect/releases/latest/download/dirless-connect-aarch64
chmod +x /usr/local/bin/dirless-connect
```

## Usage

```sh
# One-time setup: generate a keypair and verify your identity via magic link
dirless-connect ssh register

# Daily: obtain a fresh SSH certificate (valid for your org's configured TTL)
dirless-connect ssh login

# Then connect normally — the certificate is picked up automatically
ssh username@hostname
```

## Build from source

Requires [Crystal](https://crystal-lang.org) >= 1.20.0 and [just](https://github.com/casey/just).

```sh
just build-release
```

## License

Apache-2.0
