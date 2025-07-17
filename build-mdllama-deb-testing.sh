#!/usr/bin/env bash
set -e

# 1. Install build dependencies
sudo apt-get update
sudo apt-get install -y python3-pip devscripts debhelper dpkg-dev fakeroot python3-stdeb python3-all python3-requests python3-rich dh-python python3-colorama

# 2. Clone mdllama source (testing branch)
git clone --branch testing --single-branch https://github.com/QinCai-rui/mdllama.git

# 3. Build .deb package with stdeb
cd mdllama/src

cat > stdeb.cfg <<EOF
[stdeb]
Suite = testing
Architecture = all
Depends = python3, python3-requests, python3-rich, python3-colorama
EOF


# Debhelper best practice: use dh_installman via debian/python3-mdllama.manpages
# Create the manpages file for dh_installman
MANPAGE_LIST_FILE="mdllama/src/debian/python3-mdllama.manpages"
mkdir -p "mdllama/src/debian"
echo "../man/mdllama.1" > "$MANPAGE_LIST_FILE"

# Build .deb package with stdeb (dh will pick up the manpages file)

# Build .deb package with stdeb
python3 setup.py --command-packages=stdeb.command bdist_deb

# Overwrite debian/rules to ensure dh is used (so dh_installman is called)
DEB_BUILD_DIR=$(find mdllama/src -type d -name "python3-mdllama-*" | head -1)
if [ -n "$DEB_BUILD_DIR" ]; then
    echo "#!/usr/bin/make -f" > "$DEB_BUILD_DIR/debian/rules"
    echo "%:" >> "$DEB_BUILD_DIR/debian/rules"
    echo "\tdh $@" >> "$DEB_BUILD_DIR/debian/rules"
    chmod +x "$DEB_BUILD_DIR/debian/rules"

    # Ensure man page is present in the package build directory
    mkdir -p "$DEB_BUILD_DIR/debian/python3-mdllama/usr/share/man/man1"
    cp ../man/mdllama.1 "$DEB_BUILD_DIR/debian/python3-mdllama/usr/share/man/man1/"
    gzip -f "$DEB_BUILD_DIR/debian/python3-mdllama/usr/share/man/man1/mdllama.1"

    # Rebuild the package with dh
    cd "$DEB_BUILD_DIR"
    dpkg-buildpackage -rfakeroot -uc -us
    cd ../..
fi

cd ../..

# 4. Move the generated .deb to workspace root
find mdllama/src -name '*.deb' -exec cp {} . \;

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
