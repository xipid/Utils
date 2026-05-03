# GitHub Release Resolver (`ghr.sh`)

## Overview

`ghr.sh` is a utility for programmatically resolving the download URLs of assets from GitHub releases. It is primarily used as a backend for the `ipkg` utility but can be used standalone for scripting.

## Key Features

- **API Driven**: Interacts with the GitHub REST API to fetch release information.
- **Regex Filtering**: Supports filtering assets by name using regular expressions.
- **Pagination Support**: Automatically iterates through release pages until a match is found.

## Usage

### Syntax

```bash
./ghr.sh <owner/repo> [regex]
```

### Parameters

- `<owner/repo>`: The GitHub repository handle.
- `[regex]`: A case-insensitive regular expression to match the desired asset filename.

## Examples

**Get the URL of the latest release asset:**
```bash
./ghr.sh xipid/utils
```

**Get the URL of a specific .deb package:**
```bash
./ghr.sh owner/repo ".*\.deb"
```

## Technical Details

The script uses `curl` to fetch JSON data and `jq` for parsing. It specifically targets the `browser_download_url` field of the assets array.
