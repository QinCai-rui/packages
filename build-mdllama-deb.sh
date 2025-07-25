#!/usr/bin/env bash

set -e

# Clean up old repo directory before build
rm -rf repo/

# 1. Install build dependencies
sudo apt-get update
sudo apt-get install -y python3-pip devscripts debhelper dpkg-dev fakeroot python3-stdeb python3-all python3-requests python3-rich dh-python python3-colorama

# 2. Clone mdllama source
git clone https://github.com/QinCai-rui/mdllama.git


# 3. Build .deb package with stdeb
cd mdllama/src

# Fix the pyproject.toml license format issue
sed -i 's/license = "GPL-3.0-only"/license = {text = "GPL-3.0-only"}/' pyproject.toml

cat > stdeb.cfg <<EOF
[stdeb]
Suite = stable
Architecture = all
Depends = python3, python3-requests, python3-rich, python3-colorama, python3-ollama
EOF

# Create a proper debian package structure manually
PACKAGE_NAME="python3-mdllama"
VERSION=$(grep version pyproject.toml | cut -d'"' -f2)
INSTALL_DIR="deb-build"

# Create debian package structure
mkdir -p "$INSTALL_DIR/DEBIAN"
mkdir -p "$INSTALL_DIR/usr/lib/python3/dist-packages"
mkdir -p "$INSTALL_DIR/usr/bin"
mkdir -p "$INSTALL_DIR/usr/share/man/man1"

# Build the Python package
python3 setup.py build

# Copy the built package
cp -r build/lib/mdllama "$INSTALL_DIR/usr/lib/python3/dist-packages/"

# Create the executable script
cat > "$INSTALL_DIR/usr/bin/mdllama" << 'EOF'
#!/usr/bin/env python3
from mdllama.main import main
if __name__ == "__main__":
    main()
EOF
chmod +x "$INSTALL_DIR/usr/bin/mdllama"

# Copy and compress the man page
cp ../man/mdllama.1 "$INSTALL_DIR/usr/share/man/man1/"
gzip -f "$INSTALL_DIR/usr/share/man/man1/mdllama.1"

# Create the control file
cat > "$INSTALL_DIR/DEBIAN/control" << EOF
Package: $PACKAGE_NAME
Version: $VERSION
Section: python
Priority: optional
Architecture: all
Depends: python3, python3-requests, python3-rich, python3-colorama, python3-ollama
Maintainer: Raymont Qin <raymontqin_rui@outlook.com>
Description: A command-line interface for LLMs (Ollama, OpenAI-compatible)
 mdllama is a CLI tool for interacting with large language models (LLMs)
 via Ollama and OpenAI-compatible endpoints. It supports chat completions,
 interactive chat, model management, session history, and more.
EOF

# Build the deb package
dpkg-deb --build "$INSTALL_DIR" "${PACKAGE_NAME}_${VERSION}_all.deb"

# Clean up
rm -rf "$INSTALL_DIR"

# 4. Move the generated .deb to workspace root
cp python3-mdllama_*.deb ../..

cd ../..

# 5. Prepare APT repo structure

# Ensure top-level repo directory always exists first
mkdir -p repo

OLD_STABLE_DEB_DIR="oldrepo/debian/pool/main/m/mdllama"

# Remove all old .deb files from the pool before adding new ones
mkdir -p repo/pool/main/m/mdllama
rm -f repo/pool/main/m/mdllama/*.deb

# Ensure repo subdirectories exist
mkdir -p repo/dists/stable/main/binary-all

# Add the new .deb packages
cp ./*.deb repo/pool/main/m/mdllama/
echo "Added new packages to repo:"
ls -la repo/pool/main/m/mdllama/

# Keep all .deb files (all versions) - no duplicate removal for stable repo

# Move into repo directory (already ensured to exist above)
cd repo
# Use -m to include all versions in Packages file
dpkg-scanpackages -m pool /dev/null | tee dists/stable/main/binary-all/Packages | gzip -9c > dists/stable/main/binary-all/Packages.gz

# --- Instead of symlinks, COPY binary-all to all common archs for GitHub Pages compatibility ---
cd dists/stable/main
for arch in binary-amd64 binary-arm64 binary-i386 binary-armhf; do
    rm -rf "$arch"
    cp -r binary-all "$arch"
done
cd ../../../../

# Generate Release file with required metadata
mkdir -p repo/dists/stable
cat > repo/apt-ftparchive.conf <<EOF
APT::FTPArchive::Release {
  Origin "Raymont Qin";
  Label "Raymont Qin";
  Suite "stable";
  Codename "stable";
  Architectures "all amd64 arm64 i386 armhf";
  Components "main";
  Description "Raymont's personal PPA";
};
EOF

cd repo
apt-ftparchive -c=apt-ftparchive.conf release dists/stable > dists/stable/Release

# === FIX: Generate empty compressed translation and contents files in correct locations ===

# Translation files (.bz2), only need one copy each
mkdir -p dists/stable/main/i18n
echo | bzip2 > dists/stable/main/i18n/Translation-en.bz2
echo | bzip2 > dists/stable/main/i18n/Translation-en_GB.bz2

# Contents files (.gz), one per arch and for "all"
for arch in all amd64 arm64 armhf i386; do
    echo | gzip > dists/stable/main/Contents-${arch}.gz
done

# Remove any uncompressed or wrongly placed Contents/Translation files
find . -type f \( -name "Contents-*" ! -name "*.gz" -o -name "Translation-en" -o -name "Translation-en_GB" \) -delete

cd ..

# Clean up
rm -rf mdllama

echo "Done! The repo is in ./repo. Deploy it to your gh-pages branch for PPA hosting."