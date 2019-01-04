#!/bin/bash
set -e
set -x

# compat-curl-gnutls-soname4 should always be based on our native curl
# package, with the exception of being configured to use gnutls and
# carrying a patch for the soname change.
# This is required for binary compatibility with certain applications
# that believe "libcurl-gnutls.so.4" is a standard upstream soname,
# when in fact it is specific to the Debian family of distributions.
#
# Note, these applications are closed source, so there isn't much else
# we can do but provide the soname compat package

SONAME_PATCH="soname-compat.patch"

# Nuke all patches that aren't the blessed patch
echo "Wiping old patchset"
for i in $(cat series) ; do
    git rm -f $i
done

# Now copy the updated patches in from the curl package
echo "Updating to new patchset"
for i in $(cat ../curl/series) ; do
    cp -v "../curl/$i" .
done

# Update the patch series again
echo "Updating patch series"
cp -v ../curl/series .

# Clone the configures
echo "Disabling OpenSSL in configure"
cp -v ../curl/configure{,64} .
echo "--without-openssl" >> configure

# Clone the buildreqs
echo "Swapping OpenSSL for gnutls in build reqs"
cp -v ../curl/buildreq_{add,ban} .
sed -i buildreq_add -e 's/openssl/gnutls/g'
echo "openssl-dev" >> buildreq_ban

echo "Fetching curl"
CURL_URL="$(grep -E "^URL" ../curl/Makefile|cut -d = -f 2)"
mkdir staging
pushd staging
wget $CURL_URL

echo "Extracting curl"
tar xf curl*
rm *.tar.*
pushd curl*
git init
git add .
git commit -m "Initial commit"

# Apply old patches
echo "Applying old patches"
for i in $(cat ../../series|grep -v -E '.nopatch$') ; do
    patch -p1 < "../../$i"
done

# Stash patches
echo "Stashing current patchset"
git add .
git commit -m "autocommit"

echo "Patching soname"
find . -name Makefile.am | xargs -I{} sed -i {} -e 's/libcurl\.la/libcurl-gnutls.la/g'
find . -name Makefile.am | xargs -I{} sed -i {} -e 's/libcurl_la/libcurl_gnutls_la/g'
echo "Emitting patch"
git add .
git commit -s -m "Switch soname to curl-gnutls for binary compat"
git format-patch HEAD~1
mv *.patch "../../$SONAME_PATCH"
popd
popd

# Add soname patch
echo "$SONAME_PATCH" >> series

echo "Cleaning up"
rm -rf staging

echo "Now running autospec against ${CURL_URL}"
make autospec URL="$CURL_URL"
