# NOTE:
# - This file (compression_methods.sh) is sourced by genkernel.
#   Rather than changing this very file, please override specific variables
#   somewhere in /etc/genkernel.conf .
#
# - This file should not override previously defined variables, as their values may
#   originate from user changes to /etc/genkernel.conf .

GKICM_BZ2_KOPTNAME="BZIP2"
GKICM_BZ2_CMD="bzip2 -z -f -9"
GKICM_BZ2_EXT=".bz2"
GKICM_BZ2_PKG="app-arch/bzip2"

GKICM_GZ_KOPTNAME="GZIP"
GKICM_GZ_CMD="gzip -f -9"
GKICM_GZ_EXT=".gz"
GKICM_GZ_PKG="app-arch/gzip"

GKICM_LZO_KOPTNAME="LZO"
GKICM_LZO_CMD="lzop -f -9"
GKICM_LZO_EXT=".lzo"
GKICM_LZO_PKG="app-arch/lzop"

GKICM_LZ4_KOPTNAME="LZ4"
GKICM_LZ4_CMD="lz4 -f -9 -l -q"
GKICM_LZ4_EXT=".lz4"
GKICM_LZ4_PKG="app-arch/lz4"

GKICM_LZMA_KOPTNAME="LZMA"
GKICM_LZMA_CMD="lzma -z -f -9"
GKICM_LZMA_EXT=".lzma"
GKICM_LZMA_PKG="app-arch/xz-utils"

GKICM_XZ_KOPTNAME="XZ"
GKICM_XZ_CMD="xz -e --check=none -z -f -9"
GKICM_XZ_EXT=".xz"
GKICM_XZ_PKG="app-arch/xz-utils"

GKICM_ZSTD_KOPTNAME="ZSTD"
GKICM_ZSTD_CMD="zstd -f -19 -q"
GKICM_ZSTD_EXT=".zst"
GKICM_ZSTD_PKG="app-arch/zstd"
