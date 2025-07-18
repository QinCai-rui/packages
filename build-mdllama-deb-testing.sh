#!/usr/bin/env bash
set -e

# 1. Install build dependencies
sudo apt-get update
sudo apt-get install -y python3-pip devscripts debhelper dpkg-dev fakeroot python3-stdeb python3-all python3-requests python3-rich dh-python python3-colorama

# 2. Clone mdllama source (testing branch)
git clone --branch testing --single-branch https://github.com/QinCai-rui/mdllama.git

# 3. Build .deb package with stdeb
cd mdllama/src

# Fix the pyproject.toml license format issue
sed -i 's/license = "GPL-3.0-only"/license = {text = "GPL-3.0-only"}/' pyproject.toml

cat > stdeb.cfg <<EOF
[stdeb]
Suite = testing
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
OLD_STABLE_DEB_DIR="oldrepo/debian/pool/main/m/mdllama"
OLD_TESTING_DEB_DIR="oldrepo/debian-testing/pool/main/m/mdllama"
mkdir -p repo/pool/main/m/mdllama
# Skip copying any old packages - only keep the newest package being built
mkdir -p repo/dists/testing/main/binary-all

# Add the new .deb packages
cp ./*.deb repo/pool/main/m/mdllama/
echo "Added new packages to repo:"
ls -la repo/pool/main/m/mdllama/


# Remove duplicate .deb files in pool (keep all unique versions)
cd repo/pool/main/m/mdllama
ls | grep -E '\.deb$' | sort | uniq -d | xargs -r rm -v
cd -

cd repo
# Use -m to include all versions in Packages file
dpkg-scanpackages -m pool /dev/null | tee dists/testing/main/binary-all/Packages | gzip -9c > dists/testing/main/binary-all/Packages.gz

# --- Instead of symlinks, COPY binary-all to all common archs for GitHub Pages compatibility ---
cd dists/testing/main
for arch in binary-amd64 binary-arm64 binary-i386 binary-armhf; do
    rm -rf "$arch"
    cp -r binary-all "$arch"
done
cd ../../../../

# Generate Release file with required metadata
mkdir -p repo/dists/testing
cat > repo/apt-ftparchive.conf <<EOF
APT::FTPArchive::Release {
  Origin "Raymont Qin";
  Label "Raymont Qin";
  Suite "testing";
  Codename "testing";
  Architectures "all amd64 arm64 i386 armhf";
  Components "main";
  Description "Raymont's personal PPA (testing)";
};
EOF

cd repo
apt-ftparchive -c=apt-ftparchive.conf release dists/testing > dists/testing/Release

# === FIX: Generate empty compressed translation and contents files in correct locations ===

# Translation files (.bz2), only need one copy each
mkdir -p dists/testing/main/i18n
echo | bzip2 > dists/testing/main/i18n/Translation-en.bz2
echo | bzip2 > dists/testing/main/i18n/Translation-en_GB.bz2

# Contents files (.gz), one per arch and for "all"
for arch in all amd64 arm64 armhf i386; do
    echo | gzip > dists/testing/main/Contents-${arch}.gz
done

# Remove any uncompressed or wrongly placed Contents/Translation files
find . -type f \( -name "Contents-*" ! -name "*.gz" -o -name "Translation-en" -o -name "Translation-en_GB" \) -delete

cd ..

# Clean up
rm -rf mdllama

echo "Done! The repo is in ./repo. Deploy it to your gh-pages branch for PPA hosting."
