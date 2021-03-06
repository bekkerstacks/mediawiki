#!/bin/bash

# Credit to: https://github.com/benhutchins/docker-mediawiki

set -e

: ${MEDIAWIKI_SITE_NAME:=MediaWiki}
: ${MEDIAWIKI_SITE_LANG:=en}
: ${MEDIAWIKI_ADMIN_USER:=admin}
: ${MEDIAWIKI_ADMIN_PASS:=rosebud}
: ${MEDIAWIKI_DB_TYPE:=mysql}
: ${MEDIAWIKI_DB_SCHEMA:=mediawiki}
: ${MEDIAWIKI_DB_NAME:=mediawiki}
: ${MEDIAWIKI_ENABLE_SSL:=false}
: ${MEDIAWIKI_UPDATE:=false}

if [ -z "$MEDIAWIKI_DB_HOST" ]; then
	echo >&2 'error: missing MEDIAWIKI_DB_HOST environment variable'
	echo >&2 '	Did you forget to provide -e MEDIAWIKI_DB_HOST=db…?'
	echo >&2
	echo >&2 '	(Also do not forget MEDIAWIKI_DB_USER, MEDIAWIKI_DB_PASSWORD, MEDIAWIKI_DB_NAME)'
	exit 1
fi

if [ -z "$MEDIAWIKI_DB_USER" ]; then
	if [ "$MEDIAWIKI_DB_TYPE" = "mysql" ]; then
		echo >&2 'info: missing MEDIAWIKI_DB_USER environment variable, defaulting to "root"'
		MEDIAWIKI_DB_USER=root
	elif [ "$MEDIAWIKI_DB_TYPE" = "postgres" ]; then
		echo >&2 'info: missing MEDIAWIKI_DB_USER environment variable, defaulting to "postgres"'
		MEDIAWIKI_DB_USER=postgres
	else
		echo >&2 'error: missing required MEDIAWIKI_DB_USER environment variable'
		exit 1
	fi
fi

if [ -z "$MEDIAWIKI_DB_PASSWORD" ]; then
	echo >&2 'error: missing required MEDIAWIKI_DB_PASSWORD environment variable'
	echo >&2 '	Did you forget to provide -e MEDIAWIKI_DB_PASSWORD=…?'
	echo >&2
	echo >&2 '	(Also of interest might be MEDIAWIKI_DB_USER and MEDIAWIKI_DB_NAME)'
	exit 1
fi

if [ -z "$MEDIAWIKI_DB_PORT" ]; then
	if [ "$MEDIAWIKI_DB_TYPE" = "mysql" ]; then
		MEDIAWIKI_DB_PORT="3306"
	elif [ "$MEDIAWIKI_DB_TYPE" = "postgres" ]; then
		MEDIAWIKI_DB_PORT="5432"
	fi
fi

while [ `/bin/nc $MEDIAWIKI_DB_HOST $MEDIAWIKI_DB_PORT < /dev/null > /dev/null; echo $?` != 0 ]; do
	echo "Waiting for database to come up at $MEDIAWIKI_DB_HOST:$MEDIAWIKI_DB_PORT..."
	sleep 1
done

export MEDIAWIKI_DB_TYPE MEDIAWIKI_DB_HOST MEDIAWIKI_DB_USER MEDIAWIKI_DB_PASSWORD MEDIAWIKI_DB_NAME

TERM=dumb php -- <<'EOPHP'
<?php
// database might not exist, so let's try creating it (just to be safe)

if ($_ENV['MEDIAWIKI_DB_TYPE'] == 'mysql') {

	$mysql = new mysqli($_ENV['MEDIAWIKI_DB_HOST'], $_ENV['MEDIAWIKI_DB_USER'], $_ENV['MEDIAWIKI_DB_PASSWORD'], '', (int) $_ENV['MEDIAWIKI_DB_PORT']);

	if ($mysql->connect_error) {
		file_put_contents('php://stderr', 'MySQL Connection Error: (' . $mysql->connect_errno . ') ' . $mysql->connect_error . "\n");
		exit(1);
	}

	if (!$mysql->query('CREATE DATABASE IF NOT EXISTS `' . $mysql->real_escape_string($_ENV['MEDIAWIKI_DB_NAME']) . '`')) {
		file_put_contents('php://stderr', 'MySQL "CREATE DATABASE" Error: ' . $mysql->error . "\n");
		$mysql->close();
		exit(1);
	}

	$mysql->close();
}
EOPHP

if ! [ -e index.php -a -e includes/DefaultSettings.php ]; then
	echo >&2 "MediaWiki not found in $(pwd) - copying now..."

	if [ "$(ls -A)" ]; then
		echo >&2 "WARNING: $(pwd) is not empty - press Ctrl+C now if this is an error!"
		( set -x; ls -A; sleep 10 )
	fi
	tar cf - --one-file-system -C /usr/src/mediawiki . | tar xf -
	echo >&2 "Complete! MediaWiki has been successfully copied to $(pwd)"
fi

: ${MEDIAWIKI_SHARED:=/data}
if [ -d "$MEDIAWIKI_SHARED" ]; then
	if [ -e "$MEDIAWIKI_SHARED/LocalSettings.php" -a ! -e LocalSettings.php ]; then
		ln -s "$MEDIAWIKI_SHARED/LocalSettings.php" LocalSettings.php
	fi

	if [ "$(ls images)" = "README" -a ! -L images ]; then
		rm -fr images
		mkdir -p "$MEDIAWIKI_SHARED/images"
		ln -s "$MEDIAWIKI_SHARED/images" images
	fi

	if [ -d "$MEDIAWIKI_SHARED/extensions" -a ! -h /var/www/html/extensions ]; then
		echo >&2 "Found 'extensions' folder in data volume, creating symbolic link."
		rm -rf /var/www/html/extensions
		ln -s "$MEDIAWIKI_SHARED/extensions" /var/www/html/extensions
	fi

	if [ -d "$MEDIAWIKI_SHARED/skins" -a ! -h /var/www/html/skins ]; then
		echo >&2 "Found 'skins' folder in data volume, creating symbolic link."
		rm -rf /var/www/html/skins
		ln -s "$MEDIAWIKI_SHARED/skins" /var/www/html/skins
	fi

	if [ -d "$MEDIAWIKI_SHARED/vendor" -a ! -h /var/www/html/vendor ]; then
		echo >&2 "Found 'vendor' folder in data volume, creating symbolic link."
		rm -rf /var/www/html/vendor
		ln -s "$MEDIAWIKI_SHARED/vendor" /var/www/html/vendor
	fi

	if [ $MEDIAWIKI_ENABLE_SSL = true ]; then
		echo >&2 'info: enabling ssl'
		a2enmod ssl

		cp "$MEDIAWIKI_SHARED/ssl.key" /etc/apache2/ssl.key
		cp "$MEDIAWIKI_SHARED/ssl.crt" /etc/apache2/ssl.crt
		cp "$MEDIAWIKI_SHARED/ssl.bundle.crt" /etc/apache2/ssl.bundle.crt
	elif [ -e "/etc/apache2/mods-enabled/ssl.load" ]; then
		echo >&2 'warning: disabling ssl'
		a2dismod ssl
	fi
elif [ $MEDIAWIKI_ENABLE_SSL = true ]; then
	echo >&2 'error: Detected MEDIAWIKI_ENABLE_SSL flag but found no data volume';
	echo >&2 '	Did you forget to mount the volume with -v?'
	exit 1
fi

if [ ! -e "LocalSettings.php" -a ! -z "$MEDIAWIKI_SITE_SERVER" ]; then
	php maintenance/install.php \
		--confpath /var/www/html \
		--dbname "$MEDIAWIKI_DB_NAME" \
		--dbschema "$MEDIAWIKI_DB_SCHEMA" \
		--dbport "$MEDIAWIKI_DB_PORT" \
		--dbserver "$MEDIAWIKI_DB_HOST" \
		--dbtype "$MEDIAWIKI_DB_TYPE" \
		--dbuser "$MEDIAWIKI_DB_USER" \
		--dbpass "$MEDIAWIKI_DB_PASSWORD" \
		--installdbuser "$MEDIAWIKI_DB_USER" \
		--installdbpass "$MEDIAWIKI_DB_PASSWORD" \
		--server "$MEDIAWIKI_SITE_SERVER" \
		--scriptpath "" \
		--lang "$MEDIAWIKI_SITE_LANG" \
		--pass "$MEDIAWIKI_ADMIN_PASS" \
		"$MEDIAWIKI_SITE_NAME" \
		"$MEDIAWIKI_ADMIN_USER"

		if [ -d "$MEDIAWIKI_SHARED" ]; then
			if [ -e "$MEDIAWIKI_SHARED/CustomSettings.php" ]; then
				chown www-data: "$MEDIAWIKI_SHARED/CustomSettings.php"
				echo "include('$MEDIAWIKI_SHARED/CustomSettings.php');" >> LocalSettings.php
			fi

			mv LocalSettings.php "$MEDIAWIKI_SHARED/LocalSettings.php"
			ln -s "$MEDIAWIKI_SHARED/LocalSettings.php" LocalSettings.php
		fi
fi

if [ -e "$MEDIAWIKI_SHARED/composer.lock" -a -e "$MEDIAWIKI_SHARED/composer.json" ]; then
	curl -sS https://getcomposer.org/installer | php
	cp "$MEDIAWIKI_SHARED/composer.lock" composer.lock
	cp "$MEDIAWIKI_SHARED/composer.json" composer.json
	php composer.phar install --no-dev
fi

if [ -e "LocalSettings.php" -a $MEDIAWIKI_UPDATE = true ]; then
	echo >&2 'info: Running maintenance/update.php';
	php maintenance/update.php --quick
fi

mkdir -p images

chown -R www-data: .
chmod 755 images

exec "$@"
