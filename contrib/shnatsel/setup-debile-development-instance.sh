#!/bin/bash
set -e

LC_ALL=C #let our grepping be swift and merciful, and totally not stumbling on localized systems

echo "This script will set up a simple Debile instance for development purposes.
It is designed to be run on a clean (and expendable) Debian Jessie installation.
This script is DESTRUCTIVE and will EAT YOUR OS AND DATA in any other case.
Make sure you've filled in your credentials under 'users' in debile.yaml,
including the PGP key fingeprint.

Proceed? [y/N]" >&2
read REPLY
if [ "REPLY" != 'y' ]; then
    exit 1
fi

if ! [ -e contrib/shnatsel/debile.yaml ]; then
   echo "This script needs to be run from the root dir of debile git checkout." >&2
   exit 1
fi

if [ "$(id -u)" != "0" ]; then
   echo "I can't eat your data without root permissions. Sorry." >&2
   exit 1
fi

echo 'Okay, but you have been warned!' >&2

echo "deb http://ftp.debian.org/debian experimental main" >> /etc/apt/sources.list
apt-get update
apt-get -y install adduser nginx postgresql-9.4 python python2.7 python-debian python-dput python-firehose python-firewoes python-requests python-schroot python-sqlalchemy python-yaml sbuild dpkg-dev devscripts debhelper python-setuptools python-all reprepro python-flask python-sqlalchemy python-psycopg2 python-jinja2 python-debian python-six
debuild -us -uc

mkdir -p /srv/debile/incoming/UploadQueue /srv/debile/files/default /srv/debile/repo/default/conf /srv/debile/repo/default/logs /etc/debile
cp -f contrib/shnatsel/*.yaml /etc/debile/
cp -f contrib/shnatsel/reprepro-conf/* /srv/debile/repo/default/conf/
cp -f contrib/shnatsel/nginx.conf /etc/nginx/

/etc/init.d/nginx stop
/etc/init.d/nginx start

# Fire up and set up Postgres
/etc/init.d/postgresql start
createuser debile
psql --command "ALTER USER debile WITH PASSWORD 'debile';"
createdb -O debile debile

GPG_COMMAND=gpg
GPG_FLAGS=""

function get-fingerprint {
    PGP_USER_EMAIL="$1"
    GPG_FINGERPRINT=$(${GPG_COMMAND} ${GPG_FLAGS} --fingerprint ${GPG_USER_EMAIL} 2>/dev/null \
        | grep "Key fingerprint = " \
        | sed 's/Key fingerprint =//g' \
        | tr -d " " \
        | head -n 1)
    echo ${GPG_FINGERPRINT}
}

if [ "x`get-fingerprint debile@master`" = "x" ]; then
    echo "OK. I'm generating an OpenPGP key for the master."
    echo ""
    echo "  This may take a minute, please let me run."
    echo ""
    ${GPG_COMMAND} ${GPG_FLAGS} \
        -q --gen-key --batch 2>/dev/null <<EOF
            Key-Type: RSA
            Key-Length: 2048
            Name-Real: "Debile Master"
            Name-Comment: Debile Master Key
            Name-Email: debile@master
            %commit
            %echo Done
EOF
fi
MASTER_GPG_FINGERPRINT=$(get-fingerprint 'debile@master')
echo ""
echo "   The master has an OpenPGP key ${MASTER_GPG_FINGERPRINT}"
echo ""

if [ "x`get-fingerprint debile@slave`" = "x" ]; then
    echo "OK. I'm generating an OpenPGP key for the slave."
    echo ""
    echo "  This may take a minute, please let me run."
    echo ""
    ${GPG_COMMAND} ${GPG_FLAGS} \
        -q --gen-key --batch 2>/dev/null <<EOF
            Key-Type: RSA
            Key-Length: 2048
            Name-Real: Debile Slave
            Name-Comment: Debile Slave Key
            Name-Email: debile@slave
            %commit
            %echo Done
EOF
fi
SLAVE_GPG_FINGERPRINT=`get-fingerprint debile@slave`
echo ""
echo "   The slave has an OpenPGP key ${SLAVE_GPG_FINGERPRINT}"
echo ""

sed -i "s|------SLAVE-PGP-FINGERPRINT-HERE--------|${SLAVE_GPG_FINGERPRINT}|g" /etc/debile/*.yaml

cp ~/.gnupg/pubring.gpg /srv/debile/keyring.pgp

chmod -R 777 /srv/debile/ # That's right, the keys are world-writable now.

wget http://www.mux.me/debile/python-firewoes_0.2+mux_all.deb
sudo dpkg -i python-firewoes_0.2+mux_all.deb ../debile*.deb ../python-debile*.deb

debile-master-init --config /etc/debile/master.yaml /etc/debile/debile.yaml

echo "Both master and slave should be working, and you should be able to 
upload tasks to master. We've also preconfigured nginx, postgresql and reprepo.

Unfortunately we couldn't authenticate you to debile-master because of
https://github.com/opencollab/debile/issues/13. Patches are welcome." >&2
