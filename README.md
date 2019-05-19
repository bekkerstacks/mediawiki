# mediawiki
Mediawiki

## Usage

Build:

```
$ docker build -t local-mediawiki:base -f Dockerfile.base .
$ docker build -t local-mediawiki --build-arg MEDIAWIKI_VERSION=1.27 .
```

Deploy:

```
$ docker stack deploy -c docker-compose.yml wiki
```
