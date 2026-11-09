# Image du Codespace de R5.Real.10 : tout ce qui s'installe l'est ici, à la
# construction, et non dans une commande de cycle de vie relancée à chaque
# création de conteneur. Une seule image pour tous les dépôts de la ressource
# (tp1 à tp3, tp4 Neo4j, projet SteamCity) : MongoDB, Neo4j, Java, Node, gh et
# gh student. Elle est publiée sur ghcr.io par
# .github/workflows/devcontainer-publish.yml.
#
# Chaque téléchargement est figé sur une version ET vérifié par sa somme
# SHA-256, écrite ici. Changer de version, c'est changer la version et la somme
# ensemble, puis publier une nouvelle image (CONTRIBUTING.md).
#
# amd64 seulement : MongoDB ne publie pas de paquet Debian arm64 (le dépôt
# trixie/mongodb-org/9.0 n'a que mongosh en arm64). C'est l'architecture de
# Codespaces. Un Mac Apple Silicon n'est pas pris en charge : l'image n'y
# tournerait qu'en émulation, et mongod exige des instructions AVX que
# l'émulation ne fournit pas toujours (non essayé).

# Image de base des devcontainers, épinglée sur le digest de l'index
# multi-architecture de mcr.microsoft.com/devcontainers/base:2.2.5-trixie
# (Debian 13 trixie), relevé le 2026-11-09. Elle fournit l'utilisateur vscode
# (uid 1000), zsh et oh-my-zsh, git, curl et sudo : la feature common-utils y
# est déjà appliquée. trixie plutôt que bookworm : bookworm n'a plus que le
# support LTS depuis juin 2026, et MongoDB 9.0 publie des paquets pour les deux.
# Digest seul, sans le tag devant : la CLI devcontainer 0.89 ne sait pas lire
# la forme `base:2.2.5-trixie@sha256:...` (« Could not parse image name » en
# tête du journal de construction) et renonce à inspecter l'image de base avant
# de construire. L'image produite était la même, mais autant ne pas laisser
# d'erreur dans le journal.
FROM mcr.microsoft.com/devcontainers/base@sha256:71b6fe7c4e07ec747a94a72b2a17f2f8c286eaa7b1c59862888df764efb8b6c6

# Rattache le paquet publié sur ghcr.io au dépôt enseignant.
LABEL org.opencontainers.image.source="https://github.com/IUTInfoAix-R510/devcontainer" \
      org.opencontainers.image.description="Environnement de R5.Real.10 (BUT Informatique, IUT d'Aix-Marseille) : MongoDB, Neo4j, Java, Node"

# Refuse tout de suite une autre architecture plutôt que d'échouer au milieu.
RUN [ "$(dpkg --print-architecture)" = amd64 ] \
    || { echo "Image amd64 seulement : MongoDB n'a pas de paquet Debian arm64" >&2; exit 1; }

# MongoDB 9.0.4 (serveur), mongosh 2.14.1 et database tools 100.20.1
# (mongoimport, mongodump...). Les trois .deb sont pris directement dans le
# dépôt APT officiel de MongoDB pour trixie, sans ajouter ce dépôt aux sources :
# un `apt-get upgrade` ne peut pas les faire bouger. Sommes SHA-256 relevées
# dans le fichier Packages du dépôt (dists/trixie/mongodb-org/9.0, daté du
# 2026-11-02, lui-même signé par la clé « MongoDB 9 Release Signing Key »,
# empreinte B3B4 2B6C 39E5 CDDE C0A2 7E3C F366 D55B 602E 502D).
# mongodb-mongosh embarque son OpenSSL : la variante shared-openssl3 dépend de
# `libssl3`, nom que trixie a remplacé par libssl3t64.
# `apt-get install ./*.deb` installe les dépendances Debian manquantes (libcurl,
# bibliothèques Kerberos des database tools).
RUN set -eu; \
    cd /tmp; \
    base=https://repo.mongodb.org/apt/debian/dists/trixie/mongodb-org/9.0/main/binary-amd64; \
    curl -fsSLO "$base/mongodb-org-server_9.0.4_amd64.deb"; \
    curl -fsSLO "$base/mongodb-mongosh_2.14.1_amd64.deb"; \
    curl -fsSLO "$base/mongodb-database-tools_100.20.1_amd64.deb"; \
    printf '%s  %s\n' \
      f4753cec65e9ce4dd23d933f4637f5e6134ed7c0286774fb953be9a079b79e96 mongodb-org-server_9.0.4_amd64.deb \
      3c432d34b960bf3ab59932b384c54b5a768ff671ed6c4e8c6fc2de35ef170d30 mongodb-mongosh_2.14.1_amd64.deb \
      6c6d3905f98937168c33ea09bdab733156d653bfe196cad2479204f5337b216f mongodb-database-tools_100.20.1_amd64.deb \
      | sha256sum -c -; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ./mongodb-*.deb; \
    rm -f ./mongodb-*.deb; \
    rm -rf /var/lib/apt/lists/*; \
    mongod --version | grep -q '^db version v9\.0\.4$'

# Java 25 : Eclipse Temurin 25.0.5+8 (JDK complet : javac pour le projet
# SteamCity, que ./mvnw compile). Archive officielle, somme SHA-256 de la page
# de la version (identique à celle de l'API Adoptium). Neo4j 2026.10 accepte
# Java 21 et Java 25 : un seul JDK suffit, pas de second JAVA_HOME.
# Liens dans /usr/local/bin plutôt que PATH : le /etc/profile de Debian remet
# PATH à zéro dans les shells de connexion.
RUN set -eu; \
    curl -fsSL "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.5%2B8/OpenJDK25U-jdk_x64_linux_hotspot_25.0.5_8.tar.gz" -o /tmp/jdk.tgz; \
    echo "68982529869257d0ee6b824ec5aa270ff8b118bb438670da0b97ebdab178d7fb  /tmp/jdk.tgz" | sha256sum -c -; \
    mkdir -p /opt/java/openjdk; \
    tar -xzf /tmp/jdk.tgz -C /opt/java/openjdk --strip-components=1 --no-same-owner; \
    rm /tmp/jdk.tgz; \
    for b in java javac jar jshell; do ln -s "/opt/java/openjdk/bin/$b" /usr/local/bin/$b; done; \
    java -version 2>&1 | grep -q 'version "25\.0\.5"'
ENV JAVA_HOME=/opt/java/openjdk

# Node 24 LTS (« Krypton », maintenu jusqu'en avril 2028) : correcteurs et scripts
# de chargement des TP (tp1-graphe/.github/scripts, dont une dépendance,
# @neo4j-cypher/language-support, exige Node 24.11 ou plus). Archive officielle, somme
# SHA-256 de SHASUMS256.txt. Installée dans /usr/local comme dans l'image node
# officielle, sans la documentation ni les en-têtes C (include/, 65 Mo : ils
# ne servent qu'à compiler un module natif, et node-gyp sait les télécharger).
# npm ne propose plus de se mettre à jour : `npm install -g` demande root, et
# modifierait l'image. Variable d'environnement plutôt que npmrc global :
# `npm ci --prefix .github/scripts` (postCreateCommand du tp4) déplace aussi
# le npmrc global, et ne le lirait pas.
RUN set -eu; NODE=v24.22.2; \
    curl -fsSL "https://nodejs.org/dist/$NODE/node-$NODE-linux-x64.tar.xz" -o /tmp/node.tar.xz; \
    echo "48cc0e21e048790e54c0cf5749c2725005313d652651c40b7a21feb9697aaf75  /tmp/node.tar.xz" | sha256sum -c -; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
      --exclude='*/CHANGELOG.md' --exclude='*/README.md' --exclude='*/LICENSE' --exclude='*/share/doc' \
      --exclude="node-$NODE-linux-x64/include"; \
    rm /tmp/node.tar.xz; \
    [ "$(node --version)" = "$NODE" ]
ENV NPM_CONFIG_UPDATE_NOTIFIER=false

# GitHub CLI 2.103.3, paquet .deb de la page de la version, somme SHA-256 de son
# fichier gh_2.103.3_checksums.txt. Pas de feature github-cli : elle ne vérifie
# aucune somme et, si le téléchargement échoue, se rabat en silence sur la
# version précédente.
RUN set -eu; GH=2.103.3; \
    curl -fsSL "https://github.com/cli/cli/releases/download/v$GH/gh_${GH}_linux_amd64.deb" -o /tmp/gh.deb; \
    echo "e3bafef96328d1a67de3a968bdfe1cc2ffd58cf6aba8b5e201356897ed06bb3d  /tmp/gh.deb" | sha256sum -c -; \
    dpkg -i /tmp/gh.deb; \
    rm /tmp/gh.deb; \
    gh --version | head -1 | grep -q "^gh version $GH "

# Extension gh student de Classroom 50 (rendus : `gh student submit`), figée à
# v1.59.0, la version publiée avec cli-v1.59.0 dans foundation50/classroom50.
# Le binaire est posé à la main, comme le ferait
# `gh extension install foundation50/gh-student --pin v1.59.0`, sans appel à
# l'API GitHub pendant la construction (limite de débit des requêtes anonymes).
# Somme SHA-256 de checksums.txt de la version. Le manifeste reprend les champs
# qu'écrit gh (pkg/cmd/extension/manager.go) ; ispinned: true empêche
# `gh extension upgrade --all` de le déplacer.
RUN set -eu; V=v1.59.0; \
    d=/home/vscode/.local/share/gh/extensions/gh-student; \
    mkdir -p "$d"; \
    curl -fsSL "https://github.com/foundation50/gh-student/releases/download/$V/gh-student_linux-amd64" -o "$d/gh-student"; \
    echo "e8a662ac420596e55a2ea07e108ab8d738d3a6c3d69b9b800f49ac1268ab1ef2  $d/gh-student" | sha256sum -c -; \
    chmod 755 "$d/gh-student"; \
    printf 'owner: foundation50\nname: gh-student\nhost: github.com\ntag: %s\nispinned: true\npath: %s/gh-student\n' "$V" "$d" > "$d/manifest.yml"; \
    chown -R vscode:vscode /home/vscode/.local

# Neo4j 2026.10.1 Community, archive officielle (le paquet Debian tirerait un
# JDK de Debian en plus de Temurin). Somme SHA-256 du fichier .sha256 publié à
# côté de l'archive. cypher-shell et neo4j-admin sont dans l'archive.
# Réglages repris de tp1-graphe/.devcontainer/docker-compose.yml : mémoire
# limitée (tas 512m à 1G, cache de pages 256m), mot de passe « mediatheque ».
# Tout ce que Neo4j écrit (base, journaux, numéro de processus, dossier
# d'import) est déplacé dans le home de vscode, et Neo4j tourne sans root.
# /opt/neo4j appartient aussi à vscode : sinon chaque commande neo4j affiche un
# avertissement sur le propriétaire du dossier. Le dossier d'import est un lien
# que r510-neo4j relie au data/ du dépôt à chaque démarrage, le chemin du dépôt
# n'étant connu qu'à ce moment-là. Fleet Manager (supervision par la console
# Aura) est coupé, ainsi que ses annonces diffusées sur le réseau du conteneur
# (« Fleet discovery broadcasts » dans neo4j.log) : server.fleet_discovery.enabled
# est relevé dans neo4j-bolt-2026.10.1.jar, faute de documentation.
# Journaux de transactions sans préallocation, par tranches de 32 Mo : sinon
# chaque base (neo4j et system) réserve 256 Mo sur le stockage Codespaces de
# l'étudiant, pour quelques Mo de données.
# Le mot de passe initial est écrit dans la base vide par vscode, à la
# construction : aucun changement de mot de passe n'est demandé à la connexion.
RUN set -eu; V=2026.10.1; \
    curl -fsSL "https://dist.neo4j.org/neo4j-community-$V-unix.tar.gz" -o /tmp/neo4j.tgz; \
    echo "afcf4986d47d13dd908427d301d5a9278b2ec7d615a12bb40e22087c7e133e78  /tmp/neo4j.tgz" | sha256sum -c -; \
    mkdir -p /opt/neo4j; \
    tar -xzf /tmp/neo4j.tgz -C /opt/neo4j --strip-components=1 --no-same-owner; \
    rm /tmp/neo4j.tgz; \
    rm -rf /opt/neo4j/data /opt/neo4j/logs /opt/neo4j/run /opt/neo4j/import; \
    d=/home/vscode/.local/share/neo4j; \
    sed -i 's/^server\.directories\.import=/#&/' /opt/neo4j/conf/neo4j.conf; \
    printf '%s\n' \
      '' \
      '# --- Réglages de R5.Real.10 (image du Codespace) ---' \
      "server.directories.data=$d/data" \
      "server.directories.logs=$d/logs" \
      "server.directories.run=$d/run" \
      "server.directories.import=$d/import" \
      'server.memory.heap.initial_size=512m' \
      'server.memory.heap.max_size=1G' \
      'server.memory.pagecache.size=256m' \
      'dbms.usage_report.enabled=false' \
      'dbms.fleet_manager.enabled=false' \
      'server.fleet_discovery.enabled=false' \
      'db.tx_log.preallocate=false' \
      'db.tx_log.rotation.size=32M' \
      >> /opt/neo4j/conf/neo4j.conf; \
    chown -R vscode:vscode /opt/neo4j; \
    for b in neo4j neo4j-admin cypher-shell; do ln -s "/opt/neo4j/bin/$b" /usr/local/bin/$b; done; \
    install -d -o vscode -g vscode /home/vscode/.local /home/vscode/.local/share "$d" "$d/data" "$d/logs" "$d/run" "$d/import-vide"; \
    ln -s "$d/import-vide" "$d/import"; \
    chown -h vscode:vscode "$d/import"; \
    su vscode -c 'neo4j-admin dbms set-initial-password mediatheque' > /dev/null; \
    neo4j --version | grep -q "^$V$"
ENV NEO4J_HOME=/opt/neo4j

# MongoDB sans root : base et journal dans le home de vscode, cache WiredTiger
# limité à 0,25 Go (machine Codespaces de 8 Go, partagée avec Neo4j et le
# serveur de langage Java).
# r510-mongo et r510-neo4j démarrent, arrêtent et réinitialisent chaque base ;
# chaque dépôt choisit les siennes dans son postStartCommand. L'image elle-même
# ne démarre rien : une commande de cycle de vie inscrite dans l'image
# s'ajouterait à celle du dépôt au lieu d'être remplacée par elle.
COPY mongod.conf /usr/local/etc/mongod.conf
COPY r510-mongo r510-neo4j /usr/local/bin/
RUN chmod 644 /usr/local/etc/mongod.conf \
    && chmod 755 /usr/local/bin/r510-mongo /usr/local/bin/r510-neo4j \
    && install -d -o vscode -g vscode /home/vscode/.local/share/mongodb /home/vscode/.local/share/mongodb/db
