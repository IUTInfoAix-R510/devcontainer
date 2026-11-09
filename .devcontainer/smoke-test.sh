#!/bin/sh
# Smoke-test du devcontainer : prouve qu'un étudiant peut travailler dans le
# conteneur tel qu'il est distribué. Lancé par les workflows devcontainer.yml
# (vérification) et devcontainer-publish.yml (avant toute publication) et, à la
# main, par :
#   devcontainer exec --workspace-folder . .devcontainer/smoke-test.sh mongo neo4j
#
# Arguments : les bases que le postStartCommand de la configuration testée doit
# avoir démarrées (mongo, neo4j, les deux ou aucune). Les autres doivent être
# arrêtées : un dépôt MongoDB ne doit pas payer la mémoire de Neo4j. Sans
# argument (configuration source), aucune base ne doit tourner : l'image seule
# ne démarre rien.
#
# Le test arrête, tue (kill -9) et redémarre les deux bases, efface leurs
# données (reset) puis remet chaque base dans l'état où il l'a trouvée. À ne
# pas lancer dans un codespace qui contient des données auxquelles on tient.
set -eu

etape() { printf '\n→ %s\n' "$1"; }
echec() { printf '✗ %s\n' "$1" >&2; exit 1; }

NEO4J_DIR=/home/vscode/.local/share/neo4j
IMPORT=$NEO4J_DIR/import
PIDFILE=$NEO4J_DIR/run/neo4j.pid
# Dossiers temporaires et processus d'essai, nettoyés même si le test échoue.
depot=
src=
intrus=
nettoie() {
    [ -z "$intrus" ] || kill "$intrus" 2> /dev/null || true
    rm -rf "$depot" "$src"
    # Un lien d'import qui mène au faux dépôt supprimé est remis sur le dossier
    # vide.
    [ -d "$IMPORT" ] || ln -sfn "$NEO4J_DIR/import-vide" "$IMPORT"
}
trap nettoie EXIT
neo4j_pid() { pgrep -u vscode -f 'org\.neo4j\.server\.Neo4jCommunity' | head -1; }

attendu_mongo=0
attendu_neo4j=0
for base in "$@"; do
    case "$base" in
        mongo) attendu_mongo=1 ;;
        neo4j) attendu_neo4j=1 ;;
        *) echo "Usage : smoke-test.sh [mongo] [neo4j]" >&2; exit 2 ;;
    esac
done
depart=$PWD

etape "Le conteneur tourne avec l'utilisateur vscode"
[ "$(id -un)" = "vscode" ] || echec "utilisateur courant : $(id -un)"

# Les versions figées dans le Dockerfile : un écart veut dire que l'image
# testée n'est pas celle qu'on croit.
etape "Versions des outils"
mongod --version | grep -q '^db version v9\.0\.4$' || echec "mongod n'est pas en 9.0.4"
[ "$(mongosh --version)" = "2.14.1" ] || echec "mongosh n'est pas en 2.14.1"
mongoimport --version | grep -q '^mongoimport version: 100\.20\.1$' || echec "database tools ≠ 100.20.1"
[ "$(neo4j --version)" = "2026.10.1" ] || echec "neo4j n'est pas en 2026.10.1"
[ "$(cypher-shell --version)" = "Cypher-Shell 2026.10.1" ] || echec "cypher-shell n'est pas en 2026.10.1"
java -version 2>&1 | grep -q '^openjdk version "25\.0\.5"' || echec "java n'est pas en 25.0.5"
java -version 2>&1 | grep -q 'Temurin' || echec "java n'est pas Eclipse Temurin"
javac -version 2>&1 | grep -q '^javac 25\.0\.5$' || echec "javac absent ou pas en 25.0.5"
[ "${JAVA_HOME:-}" = /opt/java/openjdk ] && [ -x "$JAVA_HOME/bin/javac" ] \
    || echec "JAVA_HOME ne désigne pas le JDK de l'image (./mvnw s'en sert)"
[ "$(node --version)" = "v24.22.2" ] || echec "node n'est pas en v24.22.2"
gh --version | head -1 | grep -q '^gh version 2\.103\.3 ' || echec "gh n'est pas en 2.103.3"
mongod --version | head -1
echo "mongosh $(mongosh --version), $(mongoimport --version | head -1)"
echo "neo4j $(neo4j --version), $(cypher-shell --version)"
java -version 2>&1 | sed -n 2p
echo "node $(node --version), $(gh --version | head -1)"

# Le PATH d'un terminal VS Code est celui d'un shell de connexion : le
# /etc/profile de Debian le remet à zéro, d'où les liens dans /usr/local/bin.
etape "Les outils sont trouvés dans un shell de connexion (bash et zsh)"
for s in bash zsh; do
    for c in java javac mongosh mongoimport neo4j cypher-shell node npm gh r510-mongo r510-neo4j; do
        $s -lc "command -v $c" > /dev/null || echec "$c introuvable dans un shell de connexion $s"
    done
done

etape "gh student est installé et figé en v1.59.0"
# `gh extension list` refuse de s'exécuter sans authentification, même s'il ne
# fait aucune requête : un jeton factice suffit (dans un codespace, GITHUB_TOKEN
# est déjà défini).
GH_TOKEN=factice gh extension list | grep -E 'gh student\s+foundation50/gh-student\s+v1\.59\.0' \
    || echec "gh ne voit pas l'extension gh student en v1.59.0"
gh student --version | grep -q '^gh-student version v1\.59\.0 ' \
    || echec "gh student ne s'exécute pas ou n'est pas en v1.59.0"

etape "Les bases démarrées par postStartCommand sont celles attendues"
for base in mongo neo4j; do
    case "$base" in mongo) attendu=$attendu_mongo ;; neo4j) attendu=$attendu_neo4j ;; esac
    if r510-$base status > /dev/null; then etat=1; else etat=0; fi
    [ "$etat" = "$attendu" ] || {
        [ "$attendu" = 1 ] && echec "$base devrait tourner (postStartCommand ?)"
        echec "$base tourne alors que la configuration ne le démarre pas"
    }
    echo "$base : $([ "$etat" = 1 ] && echo démarré || echo arrêté), comme attendu"
done

# ---------------------------------------------------------------- MongoDB
etape "r510-mongo : arrêt et démarrage, chacun deux fois de suite"
r510-mongo stop > /dev/null
r510-mongo stop | grep -q 'déjà arrêté' || echec "un second stop n'est pas sans effet"
r510-mongo status > /dev/null && echec "status dit que MongoDB tourne après stop"
r510-mongo start
r510-mongo start | grep -q 'tourne déjà' || echec "un second start n'est pas sans effet"
r510-mongo status > /dev/null || echec "status dit que MongoDB est arrêté après start"

etape "MongoDB tourne sans root, avec un cache de 0,25 Go"
pgrep -x -u vscode mongod > /dev/null || echec "mongod ne tourne pas avec vscode"
cache=$(mongosh --quiet --norc --eval 'db.serverStatus().wiredTiger.cache["maximum bytes configured"]')
[ "$cache" = "268435456" ] || echec "cache WiredTiger : $cache octets au lieu de 268435456"

etape "Écriture et lecture avec mongosh, import avec mongoimport"
mongosh --quiet --norc smoke --eval '
  db.essai.drop();
  db.essai.insertOne({ ok: 1 });
  if (db.essai.countDocuments({ ok: 1 }) !== 1) quit(1);
' > /dev/null || echec "insertion ou lecture impossible"
printf '{"ville":"Aix"}\n{"ville":"Marseille"}\n' \
    | mongoimport --quiet --db smoke --collection villes --drop \
    || echec "mongoimport a échoué"
[ "$(mongosh --quiet --norc smoke --eval 'db.villes.countDocuments()')" = "2" ] \
    || echec "mongoimport n'a pas importé 2 documents"

etape "Les données survivent à un redémarrage de MongoDB"
r510-mongo stop > /dev/null
r510-mongo start > /dev/null
[ "$(mongosh --quiet --norc smoke --eval 'db.villes.countDocuments()')" = "2" ] \
    || echec "données perdues au redémarrage"

# L'arrêt d'un codespace tue mongod avec le conteneur : seule une écriture
# passée par le journal survit. j: true attend son écriture dans le journal.
etape "Une écriture journalisée survit à un arrêt brutal de MongoDB (kill -9)"
mongosh --quiet --norc smoke --eval 'db.brutal.insertOne({ ok: 1 }, { writeConcern: { j: true } })' > /dev/null \
    || echec "écriture journalisée refusée (journal désactivé ?)"
pkill -KILL -u vscode -x mongod
i=0
while pgrep -u vscode -x mongod > /dev/null; do
    i=$((i + 1)); [ "$i" -lt 50 ] || echec "mongod ne meurt pas"; sleep 0.1
done
r510-mongo start > /dev/null
[ "$(mongosh --quiet --norc smoke --eval 'db.brutal.countDocuments()')" = "1" ] \
    || echec "écriture journalisée perdue après kill -9"

etape "r510-mongo reset efface les bases, et seulement s'il est confirmé"
r510-mongo reset < /dev/null > /dev/null 2>&1 && echec "reset sans confirmation a été accepté"
[ "$(mongosh --quiet --norc smoke --eval 'db.villes.countDocuments()')" = "2" ] \
    || echec "reset sans confirmation a effacé des données"
r510-mongo reset --oui > /dev/null
[ "$(mongosh --quiet --norc smoke --eval 'db.villes.countDocuments()')" = "0" ] \
    || echec "reset --oui n'a pas effacé la base smoke"

# ---------------------------------------------------------------- Neo4j
# Le dossier d'import est relié au data/ du dépôt d'où r510-neo4j start est
# lancé : un faux dépôt git dans un dossier temporaire le vérifie.
etape "r510-neo4j : arrêt et démarrage, chacun deux fois de suite"
depot=$(mktemp -d)
git init -q "$depot"
mkdir "$depot/data"
printf 'id,nom\n1,Aix\n2,Marseille\n' > "$depot/data/essai.csv"
r510-neo4j stop > /dev/null
r510-neo4j stop | grep -q 'déjà arrêté' || echec "un second stop n'est pas sans effet"
r510-neo4j status > /dev/null && echec "status dit que Neo4j tourne après stop"

# Après un arrêt brutal, neo4j.pid reste en place et son numéro peut être
# repris par un autre processus : ni status, ni stop, ni start ne doivent le
# prendre pour Neo4j.
etape "Un neo4j.pid périmé, repris par un autre processus, est ignoré"
sleep 300 &
intrus=$!
echo "$intrus" > "$PIDFILE"
r510-neo4j status > /dev/null && echec "status prend le processus $intrus pour Neo4j"
r510-neo4j stop | grep -q 'déjà arrêté' || echec "stop croit Neo4j démarré"
kill -0 "$intrus" 2> /dev/null || echec "stop a tué un processus étranger à Neo4j"
echo "$intrus" > "$PIDFILE"
debut=$(date +%s)
(cd "$depot" && r510-neo4j start)
echo "Neo4j prêt en $(($(date +%s) - debut)) s"
(cd "$depot" && r510-neo4j start) | grep -q 'tourne déjà' || echec "un second start n'est pas sans effet"
r510-neo4j status > /dev/null || echec "status dit que Neo4j est arrêté après start"
kill -0 "$intrus" 2> /dev/null || echec "start a tué un processus étranger à Neo4j"
kill "$intrus"
intrus=

etape "Neo4j tourne sans root et accepte le mot de passe du TP"
ps -o user= -p "$(neo4j_pid)" | grep -q '^vscode$' \
    || echec "Neo4j ne tourne pas avec vscode"
cypher() { cypher-shell -u neo4j -p mediatheque --format plain "$1" | tail -1; }
[ "$(cypher 'RETURN 1 AS n;')" = "1" ] || echec "cypher-shell n'obtient pas de réponse"

etape "LOAD CSV lit le data/ du dépôt, même après un start lancé d'ailleurs"
[ "$(readlink "$IMPORT")" = "$depot/data" ] || echec "le dossier d'import n'est pas relié à data/"
# Depuis un sous-dossier du dépôt : la racine git est retrouvée.
(cd "$depot/data" && r510-neo4j start > /dev/null)
[ "$(readlink "$IMPORT")" = "$depot/data" ] || echec "start lancé depuis data/ a décroché l'import"
# Hors de tout dépôt (comme depuis ~ dans un codespace) : le lien est gardé.
(cd / && env -u CODESPACE_VSCODE_FOLDER r510-neo4j start > /dev/null)
[ "$(readlink "$IMPORT")" = "$depot/data" ] || echec "start lancé hors du dépôt a décroché l'import"
n=$(cypher 'LOAD CSV WITH HEADERS FROM "file:///essai.csv" AS l CREATE (:Ville {id: toInteger(l.id), nom: l.nom}) RETURN count(*) AS n;')
[ "$n" = "2" ] || echec "LOAD CSV a lu $n lignes au lieu de 2"

etape "Les données survivent à un redémarrage de Neo4j"
r510-neo4j stop > /dev/null
(cd "$depot" && r510-neo4j start > /dev/null)
[ "$(cypher 'MATCH (v:Ville) RETURN count(v) AS n;')" = "2" ] || echec "données perdues au redémarrage"

# Comme mongod, Neo4j est tué avec le conteneur à l'arrêt du codespace.
etape "Les données survivent à un arrêt brutal de Neo4j (kill -9)"
p=$(neo4j_pid)
kill -KILL "$p"
i=0
while kill -0 "$p" 2> /dev/null; do
    i=$((i + 1)); [ "$i" -lt 50 ] || echec "Neo4j ne meurt pas"; sleep 0.1
done
r510-neo4j status > /dev/null && echec "status dit que Neo4j tourne après kill -9"
(cd "$depot" && r510-neo4j start > /dev/null)
[ "$(cypher 'MATCH (v:Ville) RETURN count(v) AS n;')" = "2" ] || echec "données perdues après kill -9"

etape "r510-neo4j reset efface la base et remet le mot de passe du TP"
r510-neo4j reset < /dev/null > /dev/null 2>&1 && echec "reset sans confirmation a été accepté"
(cd "$depot" && r510-neo4j reset --oui > /dev/null)
[ "$(cypher 'MATCH (n) RETURN count(n) AS n;')" = "0" ] || echec "reset --oui n'a pas vidé la base"

# ---------------------------------------------------------------- Java
etape "Java compile et exécute un programme"
src=$(mktemp -d)
printf 'public class Essai { public static void main(String[] a) { System.out.println("ok"); } }\n' > "$src/Essai.java"
javac -d "$src" "$src/Essai.java" || echec "javac ne compile pas"
[ "$(java -cp "$src" Essai)" = "ok" ] || echec "java n'exécute pas la classe compilée"
# Fichier source compact (Java 25, JEP 512), lancé sans compilation préalable.
printf 'void main() { IO.println("ok"); }\n' > "$src/Compact.java"
[ "$(java "$src/Compact.java")" = "ok" ] || echec "java n'exécute pas un fichier source compact"
rm -rf "$src"
src=

# ---------------------------------------------------------------- Mémoire
# Les deux bases tournent, à vide, depuis une quinzaine de secondes : c'est
# leur coût au repos sur la machine de 8 Go.
etape "Mémoire résidente au repos (les deux bases démarrées)"
sleep 15
rss() { ps -o rss= -p "$1" | awk '{ printf "%d Mo", $1 / 1024 }'; }
echo "MongoDB : $(rss "$(pgrep -u vscode -x mongod)")"
echo "Neo4j   : $(rss "$(neo4j_pid)")"
if [ -r /sys/fs/cgroup/memory.current ]; then
    awk '{ printf "Conteneur entier (cgroup) : %d Mo\n", $1 / 1048576 }' /sys/fs/cgroup/memory.current
fi
# Les données des bases comptent dans le stockage Codespaces de l'étudiant.
echo "Disque : MongoDB $(du -sm /home/vscode/.local/share/mongodb | cut -f1) Mo, Neo4j $(du -sm "$NEO4J_DIR" | cut -f1) Mo"

# Les ports des bases ne doivent être joignables que depuis le conteneur.
# Neo4j écoute sur une socket IPv6 à adresse IPv4 (::ffff:127.0.0.1).
etape "Les bases n'écoutent que sur localhost"
ss -lnt | awk '$4 ~ /:(27017|7474|7687)$/ && $4 !~ /^(127\.0\.0\.1|\[::1\]|\[::ffff:127\.0\.0\.1\]):/' | grep . \
    && echec "une base écoute hors de localhost"
echo "27017, 7474 et 7687 : localhost seulement"

# Remet chaque base dans l'état laissé par postStartCommand.
cd "$depart"
rm -rf "$depot"
depot=
[ -d "$IMPORT" ] || ln -sfn "$NEO4J_DIR/import-vide" "$IMPORT"
if [ "$attendu_mongo" = 0 ]; then r510-mongo stop > /dev/null; fi
if [ "$attendu_neo4j" = 1 ]; then r510-neo4j start > /dev/null; else r510-neo4j stop > /dev/null; fi

printf '\n✓ Le conteneur est prêt pour la séance\n'
