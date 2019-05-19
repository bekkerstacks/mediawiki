FROM local-mediawiki:base

ARG MEDIAWIKI_VERSION

RUN MW_VER_MAJOR_PLUS_MINOR=$(php -r '$parts=explode(".", $_ENV["MEDIAWIKI_VERSION"], 3); echo "{$parts[0]}.{$parts[1]}";'); \
    MEDIAWIKI_DOWNLOAD_URL="https://releases.wikimedia.org/mediawiki/$MW_VER_MAJOR_PLUS_MINOR/mediawiki-$MEDIAWIKI_VERSION.1.tar.gz"; \
    set -x; \
    mkdir -p /usr/src/mediawiki \
    && curl -fSL "$MEDIAWIKI_DOWNLOAD_URL" -o mediawiki.tar.gz \
    && curl -fSL "${MEDIAWIKI_DOWNLOAD_URL}.sig" -o mediawiki.tar.gz.sig \
    && tar -xf mediawiki.tar.gz -C /usr/src/mediawiki --strip-components=1 \
    && rm -f mediawiki.tar.gz mediawiki.tar.gz.sig
