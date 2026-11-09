# Guide de contribution

Ce dépôt ne contient que l'image du Codespace de R5.Real.10 : sa recette, son smoke-test, les workflows qui la vérifient et la publient, et les modèles de configuration des dépôts de TP. Le [README](README.md) explique comment s'en servir dans un dépôt de TP.

## Structure du dépôt

```
.devcontainer/
├── devcontainer.json          configuration distribuée de CE dépôt (image publiée, les deux bases)
├── smoke-test.sh              smoke-test, lancé avant toute publication et chaque semaine
└── source/                    configuration source : construction de l'image, et secours
    ├── Dockerfile             tout ce qui s'installe, versions figées et sommes SHA-256
    ├── devcontainer.json      feature sshd, extensions, réglages VS Code, remoteUser, ports
    ├── devcontainer-lock.json version et digest de la feature sshd
    ├── mongod.conf            MongoDB sans root, cache de 0,25 Go
    ├── r510-mongo             start | stop | status | reset | log
    └── r510-neo4j             start | stop | status | reset | log
exemples/
├── mongodb/devcontainer.json       tp1 à tp3, projet (configuration par défaut)
├── neo4j/devcontainer.json         tp4 Neo4j (issu de tp1-graphe)
└── projet-bonus/devcontainer.json  projet, bonus Neo4j (.devcontainer/bonus-neo4j/ du dépôt)
.github/workflows/
├── devcontainer.yml           vérification : même tag partout, source, image distribuée et les trois modèles
└── devcontainer-publish.yml   publication sur ghcr.io, sur tag devcontainer-AAAA.MM.N
```

## Le conteneur du Codespace

### Deux configurations, et des modèles

Classroom 50 crée le dépôt de chaque étudiant à partir d'un dépôt modèle, dans l'organisation de classe `IUTInfoAix-R510-2026`. Les prebuilds Codespaces des dépôts modèles ne s'appliquent pas à ces copies, et des prebuilds sur les copies seraient facturés à l'organisation de classe, dont le budget Codespaces est à 0 $ : sans précaution, chaque étudiant reconstruirait toute l'image au début de la séance. D'où deux configurations, comme dans IntroPython.

| Configuration | Fichiers | Rôle |
|---|---|---|
| Source | [.devcontainer/source/](.devcontainer/source/) | Le Dockerfile, la feature sshd, les extensions et les réglages VS Code. Elle sert à fabriquer l'image publiée, et de secours si celle-ci est indisponible (« New with options… » dans ce dépôt). |
| Distribuée | [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) et [exemples/](exemples/) | Une image déjà construite, publiée sur ghcr.io et désignée par un tag épinglé, la machine (`hostRequirements`) et un `postStartCommand` qui choisit les bases à démarrer. Chaque dépôt de TP en copie une. |

Tout se modifie dans la configuration source. Les extensions, les réglages, l'utilisateur `vscode` et les ports sont inscrits dans l'image à la construction (label `devcontainer.metadata`). Une configuration distribuée ne contient que le nom de l'image, `hostRequirements`, son `postStartCommand` et, pour un dépôt qui en a, l'installation de ses dépendances npm. `hostRequirements` est aussi dans l'image, mais Codespaces choisit la machine avant de la télécharger : seul celui du dépôt compte.

Conséquence : **un changement de la configuration source n'arrive chez les étudiants qu'après la publication d'une nouvelle image, puis la mise à jour du tag dans chaque dépôt modèle.**

Une seule image sert tous les dépôts. Les bases ne sont pas démarrées par l'image mais par le `postStartCommand` de chaque dépôt, pour qu'un dépôt MongoDB ne paie pas les 800 Mo de Neo4j (voir « Pas de postStartCommand dans l'image » plus bas).

### Reconstruire et tester en local

Il faut Docker et la CLI des dev containers (`npm install -g @devcontainers/cli`).

```bash
# Construire l'image depuis la configuration source, sans cache
devcontainer build --workspace-folder . --config .devcontainer/source/devcontainer.json \
  --image-name r510-devcontainer:local --no-cache

# Démarrer un conteneur neuf à partir de cette image
devcontainer up --workspace-folder . --config .devcontainer/source/devcontainer.json --remove-existing-container

# Lancer le smoke-test dans le conteneur (aucune base attendue au départ)
devcontainer exec --workspace-folder . --config .devcontainer/source/devcontainer.json .devcontainer/smoke-test.sh
```

Pour tester un modèle avec l'image locale avant de la publier, copiez-le hors du dépôt en remplaçant l'image par `r510-devcontainer:local`, puis passez au smoke-test les bases que son `postStartCommand` démarre :

```bash
mkdir -p /tmp/r510/neo4j
sed 's#ghcr.io/iutinfoaix-r510/r510-devcontainer:[0-9.]*#r510-devcontainer:local#' \
  exemples/neo4j/devcontainer.json > /tmp/r510/neo4j/devcontainer.json
devcontainer up --workspace-folder . --config /tmp/r510/neo4j/devcontainer.json --remove-existing-container
devcontainer exec --workspace-folder . --config /tmp/r510/neo4j/devcontainer.json .devcontainer/smoke-test.sh neo4j
```

Pour approcher la machine d'un codespace, limitez le conteneur à 2 cœurs et 8 Go avant le smoke-test : `docker update --cpus 2 --memory 8g --memory-swap 8g <conteneur>`.

Le smoke-test ([.devcontainer/smoke-test.sh](.devcontainer/smoke-test.sh)) vérifie qu'un étudiant peut travailler :

- le conteneur tourne avec l'utilisateur `vscode` ;
- chaque outil est à la version figée dans le Dockerfile, et trouvé dans un shell de connexion bash et zsh ;
- `gh student` est installé, en v1.59.0 et épinglé ;
- les bases qui tournent au départ sont exactement celles passées en argument (celles du `postStartCommand`) ;
- pour chaque base : `stop` et `start` deux fois de suite sans erreur, processus de `vscode`, écriture et lecture, données conservées après un redémarrage et après un `kill -9` (ce que subissent les bases à l'arrêt d'un codespace), `reset` refusé sans confirmation puis effectif avec `--oui` ;
- MongoDB : cache WiredTiger de 0,25 Go, `mongoimport` ;
- Neo4j : un `neo4j.pid` dont le numéro a été repris par un autre processus n'empêche pas le démarrage, et ce processus n'est pas tué ; mot de passe `mediatheque` ; `LOAD CSV` depuis le `data/` d'un dépôt, y compris après un `start` lancé depuis un sous-dossier ou hors du dépôt ;
- `javac` compile et `java` exécute, y compris un fichier source compact de Java 25 ;
- la mémoire résidente des deux bases au repos et leur place sur le disque sont affichées ;
- les ports 27017, 7474 et 7687 n'écoutent que sur localhost.

Il dure deux à trois minutes, dont une cinquantaine de secondes d'arrêts de Neo4j. Il efface les données des deux bases : ne le lancez pas dans un codespace où elles comptent.

### Vérification continue

Le workflow [devcontainer.yml](.github/workflows/devcontainer.yml) vérifie d'abord que les quatre configurations distribuées désignent le même tag de l'image, puis lance le smoke-test sur cinq configurations : la source (construite), la configuration distribuée de ce dépôt et les trois modèles de `exemples/` (image téléchargée). Il tourne à chaque push ou PR qui touche `.devcontainer/` ou `exemples/`, chaque lundi, et à la main. L'image distribuée y est téléchargée sans authentification, comme chez un étudiant : le job échoue si le paquet a disparu ou n'est plus public.

**Lancez-le à la main la veille d'une séance** (onglet Actions, workflow `devcontainer`, **Run workflow**).

Tant qu'une nouvelle version n'est pas publiée, les quatre jobs « image distribuée » et « modèle » échouent sur une branche qui y renvoie déjà : c'est attendu. D'où l'ordre de la section suivante.

Les workflows portent la garde `if: github.repository == 'IUTInfoAix-R510/devcontainer'` : ils ne tournent pas dans un fork.

### Publier une nouvelle image

À faire quand un fichier de `.devcontainer/source/` change.

1. Choisissez une version au format `AAAA.MM.N`, par exemple `2026.12.1`. Jamais `latest`, et jamais une version déjà publiée : les dépôts étudiants existants pointent dessus.
2. Mettez cette version dans [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) et dans les trois fichiers de [exemples/](exemples/), puis commitez sur une branche. Le job « même version de l'image partout » échoue si l'un des quatre est oublié.
3. Publiez l'image depuis cette branche en poussant un tag git :
   ```bash
   git tag devcontainer-2026.12.1
   git push origin devcontainer-2026.12.1
   ```
   Le workflow [devcontainer-publish.yml](.github/workflows/devcontainer-publish.yml) construit l'image sans cache, lance le smoke-test et ne publie que s'il réussit.
4. Relancez le workflow `devcontainer` sur la branche : ses six jobs doivent passer.
5. Fusionnez dans `main`.
6. Mettez la nouvelle version dans chaque dépôt modèle : `.devcontainer/devcontainer.json` de tp1, tp2, tp3, tp4 et du projet, et `.devcontainer/bonus-neo4j/devcontainer.json` du projet.

L'ordre compte : un dépôt modèle qui pointe sur une version pas encore publiée produit des codespaces qui échouent à la création.

**À la première publication seulement**, le paquet est créé privé, et l'offre de l'organisation ne permet pas la visibilité « internal ». Rendez-le public avant l'étape 4 : page du paquet `r510-devcontainer` dans l'organisation IUTInfoAix-R510, **Package settings**, **Change visibility**. Les codespaces des étudiants sont créés dans une autre organisation (`IUTInfoAix-R510-2026`) et le téléchargent sans authentification. Vérifiez ensuite le téléchargement anonyme :

```bash
docker logout ghcr.io
docker pull ghcr.io/iutinfoaix-r510/r510-devcontainer:2026.11.1
```

Le nom du paquet est en minuscules : ghcr.io refuse `IUTInfoAix-R510` dans un nom d'image (« repository name must be lowercase »).

Une fois le workflow présent sur `main`, la publication peut aussi se lancer depuis l'onglet Actions (workflow `devcontainer-publish`, **Run workflow**, en saisissant la version).

Les dépôts étudiants déjà créés gardent la version qu'ils référencent : une nouvelle image ne profite qu'aux dépôts créés ensuite.

### Changer la version d'un outil

Chaque téléchargement du Dockerfile est figé sur une version **et** vérifié par sa somme SHA-256. Changer de version, c'est changer les deux, puis mettre à jour la version attendue par le smoke-test.

| Outil | Où trouver la somme |
|---|---|
| Image de base | `docker buildx imagetools inspect mcr.microsoft.com/devcontainers/base:<tag>` : digest de l'index (ligne `Digest:`) |
| MongoDB, mongosh, database tools | fichier `Packages` de `https://repo.mongodb.org/apt/debian/dists/trixie/mongodb-org/9.0/main/binary-amd64/`, champ `SHA256` |
| Temurin | fichier `.sha256.txt` à côté de l'archive, sur la page de la version (adoptium/temurin25-binaries) |
| Node | `https://nodejs.org/dist/<version>/SHASUMS256.txt` |
| gh | `gh_<version>_checksums.txt` de la version (cli/cli) |
| gh student | `checksums.txt` de la version (foundation50/gh-student) ; la version suit `cli-vX.Y.Z` de foundation50/classroom50 |
| Neo4j | `https://dist.neo4j.org/neo4j-community-<version>-unix.tar.gz.sha256` |
| feature sshd | `devcontainer upgrade --workspace-folder . --config .devcontainer/source/devcontainer.json` réécrit `devcontainer-lock.json` |

### Choix à connaître avant de modifier le conteneur

**Pas de postStartCommand dans l'image.** Une commande de cycle de vie inscrite dans la configuration source passe dans les métadonnées de l'image. Or, quand une image porte un `postStartCommand` et que le dépôt en déclare un autre, les deux s'exécutent : la spécification fusionne les commandes de cycle de vie au lieu de remplacer celle de l'image ([containers.dev, Merge Logic](https://containers.dev/implementors/spec/#merge-logic)). Un dépôt Neo4j ne pourrait plus éviter de démarrer MongoDB. Le choix des bases est donc laissé au `postStartCommand` de chaque dépôt, et l'image seule ne démarre rien (le smoke-test de la configuration source le vérifie). Quand un dépôt démarre les deux bases, son `postStartCommand` est un objet : les deux commandes tournent en parallèle, et l'échec de l'une n'empêche pas l'autre.

**Une seule image pour toute la ressource.** Elle pèse 1,12 Go compressés, contre 190 Mo pour IntroPython. Des images séparées (MongoDB seul, Neo4j seul) gagneraient quelques centaines de Mo chacune, au prix de plusieurs publications à tenir à jour et d'un projet bonus qui a besoin des deux bases.

**Image de base `devcontainers/base` en trixie, épinglée par digest.** Elle fournit l'utilisateur `vscode`, zsh, git et sudo (la feature common-utils y est déjà appliquée, d'où son absence ici). Le digest est écrit seul, sans le tag : la CLI devcontainer 0.89 ne sait pas lire la forme `base:2.2.5-trixie@sha256:…` et l'écrit en erreur dans le journal de construction. L'image `devcontainers/java` existe en Java 25, mais elle installe un OpenJDK Microsoft « current » sans version figée : Temurin posé à la main est aussi simple et vérifiable.

**MongoDB pris en `.deb` sans ajouter le dépôt APT.** Les trois paquets sont téléchargés directement depuis le dépôt de MongoDB, vérifiés, puis installés avec `apt-get install ./*.deb`. Sans le dépôt dans les sources, un `apt-get upgrade` ne peut pas les déplacer. La variante `mongodb-mongosh-shared-openssl3` ne s'installe pas sur trixie (elle dépend de `libssl3`, renommé `libssl3t64`) : c'est `mongodb-mongosh`, qui embarque son OpenSSL.

**amd64 seulement.** MongoDB ne publie pas de paquet Debian arm64 (le dépôt trixie n'a que mongosh en arm64). Le Dockerfile refuse toute autre architecture dès sa première instruction RUN. Un Mac Apple Silicon n'est pas pris en charge : l'image n'y tournerait qu'en émulation, et mongod exige des instructions AVX que l'émulation ne fournit pas toujours. Cela n'a pas été essayé.

**MongoDB 9.0 et non 8.0.** La 8.0.34 ne démarre pas sur un noyau Linux 7.0 (SERVER-131779). La 9.0.4 démarre sur ce noyau (essai local de novembre 2026) ; le noyau des hôtes Codespaces reste à vérifier.

**Les bases tournent sans root, données dans le home.** `mongod` est lancé par `vscode` avec [mongod.conf](.devcontainer/source/mongod.conf) (`fork: true` : la commande rend la main une fois le serveur prêt). Neo4j écrit sa base, ses journaux, son numéro de processus et son dossier d'import sous `~/.local/share/neo4j` (réglages `server.directories.*` ajoutés à `neo4j.conf`). Les données survivent à l'arrêt d'un codespace, pas à un « Rebuild Container ». Garder les bases dans un dossier de `/workspaces` hors du dépôt les ferait survivre au rebuild ; ce n'est pas fait, et Codespaces n'a pas été essayé ainsi.

**Les bases sont tuées à l'arrêt du codespace.** L'arrêt du conteneur tue tous ses processus sans passer par `r510-mongo stop` ni `r510-neo4j stop`. Les bases repartent sur leur journal (WiredTiger, journaux de transactions de Neo4j) : le smoke-test le vérifie avec un `kill -9`, et trois cycles `docker stop` puis `devcontainer up` ont gardé les données en local. Le fichier `neo4j.pid` reste alors en place, et son numéro peut être repris par un autre processus à la reprise. `neo4j status` se contente de vérifier qu'un processus porte ce numéro : `r510-neo4j` vérifie à la place, dans `/proc`, que c'est bien un serveur Neo4j, et supprime le fichier sinon. Cette vérification ne lance pas de JVM, contrairement à `neo4j status`.

**Dossier d'import de Neo4j.** `r510-neo4j start` cherche `data/` dans le dossier courant, puis à la racine du dépôt git qui le contient, puis dans `$CODESPACE_VSCODE_FOLDER`. S'il n'en trouve aucun, il garde le lien actuel tant qu'il mène à un dossier, et ne le relie au dossier vide `import-vide` qu'en dernier recours. Un étudiant qui lance `start` ou `reset` depuis `~` ou un sous-dossier ne décroche donc pas l'import.

**Disque économisé sur le quota des étudiants.** Avec une image personnalisée, le conteneur compte dans le stockage Codespaces facturé à l'étudiant ([facturation de Codespaces](https://docs.github.com/en/billing/concepts/product-billing/github-codespaces), « Storage volume for codespaces built from custom configurations »), dont le quota gratuit est de 15 Go-mois. Les bases ne préallouent donc pas leur journal : `log=(prealloc=false,file_max=20MB)` pour WiredTiger (`configString` de `mongod.conf`), `db.tx_log.preallocate=false` et `db.tx_log.rotation.size=32M` pour Neo4j. Après le smoke-test, MongoDB occupe 21 Mo et Neo4j 3 Mo, contre environ 200 Mo et 517 Mo avec les réglages par défaut. Node est installé sans ses en-têtes C (`include/`), qui ne servent qu'à compiler un module natif.

**Deux avertissements de MongoDB corrigés sans root.** `r510-mongo` relève la limite souple de fichiers ouverts (`ulimit -Sn 64000`) et désactive rseq de la glibc (`GLIBC_TUNABLES=glibc.pthread.rseq=0`) : sans cela, mongosh les affiche à chaque connexion. Ceux qui dépendent de l'hôte (huge pages, swappiness) et « Access control is not enabled » restent.

**Mémoire limitée.** Cache WiredTiger de 0,25 Go au lieu de 3,5 Go par défaut sur 8 Go. Neo4j reprend les réglages de tp1-graphe (tas de 512 Mo à 1 Go, cache de pages de 256 Mo). Fleet Manager est coupé (`dbms.fleet_manager.enabled`, `server.fleet_discovery.enabled`) : sans cela, Neo4j diffuse des annonces sur le réseau du conteneur. Ce second réglage a été relevé dans `neo4j-bolt-2026.10.1.jar`, faute de documentation : vérifiez-le à chaque changement de version de Neo4j (le message « Fleet discovery broadcasts have been enabled » ne doit plus apparaître dans `r510-neo4j log`).

**Mot de passe Neo4j écrit à la construction.** `neo4j-admin dbms set-initial-password mediatheque` est exécuté par `vscode` dans le Dockerfile : aucun changement de mot de passe n'est demandé à la première connexion. `r510-neo4j reset` le réécrit. Les bases n'écoutent que sur localhost (le smoke-test le vérifie), et leurs ports sont privés : ce mot de passe connu de tous et MongoDB sans authentification ne posent problème que si un étudiant rend un port public.

**Liens dans `/usr/local/bin` plutôt qu'un `ENV PATH`.** Le `/etc/profile` de Debian remet `PATH` à zéro dans les shells de connexion, ceux des terminaux VS Code. Java, Neo4j et cypher-shell sont donc reliés dans `/usr/local/bin` ; le smoke-test vérifie chaque outil avec `bash -lc` et `zsh -lc`.

**npm ne propose pas de se mettre à jour.** `npm install -g npm@…` demande root et modifierait l'image. Le réglage passe par `NPM_CONFIG_UPDATE_NOTIFIER=false` et non par le npmrc global : `npm ci --prefix .github/scripts`, le `postCreateCommand` du tp4, déplace aussi le npmrc global et ne le lirait pas.

**Pas de feature github-cli.** Elle ne vérifie aucune somme et, si le téléchargement échoue, se rabat en silence sur la version précédente (`install.sh`, fonction `install_deb_using_github`). Son option `extensions` ne sait pas figer une version. Le `.deb` de gh est donc vérifié et installé dans le Dockerfile, et le binaire de gh student posé à la main avec le manifeste qu'écrirait `gh extension install foundation50/gh-student --pin v1.59.0` (`ispinned: true`). Les rendus se font par tag `submit/…` (guide Classroom 50, §7) : gh student n'est là qu'en secours.

**Feature sshd.** L'image de base n'a pas de serveur SSH, que `gh codespace ssh` exige hors de l'image par défaut de Codespaces. Il écoute sur le port 2222 du conteneur, qui n'est pas redirigé, et le compte `vscode` n'a pas de mot de passe. La feature ajoute à Copilot une consigne qui conseille d'en créer un : la configuration source vide `github.copilot.chat.codeGeneration.instructions`, ce qui retire aussi la consigne de la feature git de l'image de base.

**Extensions dans l'image, pack Java compris.** Les dépôts MongoDB reçoivent aussi le pack Java, qui ne s'active que s'il trouve du Java ou un `pom.xml` : il coûte un téléchargement à la création du codespace, pas de mémoire. Ne le retirez pas sans vérifier les modèles de `exemples/`, qui n'ajoutent aucune extension.

**Copilot en tuteur.** Copilot Chat est installé, mais `github.copilot.enable` coupe les complétions automatiques pendant la frappe, comme dans IntroPython : l'étudiant écrit son code, Copilot ne répond que dans le chat.

**Pas de Maven dans l'image.** Le projet SteamCity utilise le wrapper `./mvnw`, qui télécharge Maven et les dépendances dans `~/.m2` à la première compilation. Le smoke-test vérifie seulement `JAVA_HOME`, dont le wrapper se sert.

**Pas de variables d'environnement de connexion.** Les correcteurs et scripts des TP ont déjà `mongodb://localhost:27017` et `bolt://localhost:7687` par défaut. Un `MONGODB_URI` défini dans l'image l'emporterait sur le `.env` du tp2, que dotenv ne remplace pas.

### Mesures

Mesures locales du 9 novembre 2026, avec la CLI `devcontainer` 0.89.0 et Docker 29.9, sur un poste de 16 cœurs et 32 Go, noyau Linux 7.0. Le smoke-test et les durées des commandes `r510-*` sont mesurés dans un conteneur limité à 2 cœurs et 8 Go (`docker update`), le reste sans limite. L'installation des extensions VS Code n'y est pas comptée, et ces durées ne sont pas celles d'un codespace.

| Mesure | Valeur |
|---|---|
| Construction depuis zéro (image de base en cache, sans cache de construction) | 104 s |
| Taille de l'image, décompressée | 3,73 Go |
| Taille de l'image, compressée (ce que télécharge un codespace) | 1,12 Go, dont 388 Mo pour l'image de base |
| Démarrage nu d'un conteneur (`docker run … true`) | 0,45 à 0,48 s |
| `devcontainer up` depuis l'image locale, modèle MongoDB (`r510-mongo start` compris) | 2,6 à 4,0 s |
| … modèle Neo4j (`r510-neo4j start` compris) | 9,4 à 15,2 s |
| … modèle projet avec bonus (les deux bases) | 9,3 à 9,5 s |
| Neo4j, de `start` à la première requête | 7 à 13 s |
| Neo4j, `stop` | 16 s |
| MongoDB, `start` et `stop` | 0,6 s et 1,1 s |
| `r510-neo4j status` | 15 ms |
| Smoke-test complet | 123 à 162 s |
| Mémoire résidente au repos : MongoDB | 140 à 151 Mo |
| Mémoire résidente au repos : Neo4j | 803 à 817 Mo |
| Mémoire du conteneur entier (cgroup), les deux bases au repos | 992 Mo à 1,01 Go |
| Disque des bases après le smoke-test : MongoDB, Neo4j | 21 Mo, 3 Mo |

Couches les plus lourdes de l'image (décompressées) : MongoDB 770 Mo (mongod et mongosh pèsent chacun près de 300 Mo), Temurin 317 Mo, Neo4j 272 Mo, Node 143 Mo, gh 44 Mo, sshd 28 Mo, gh student 10 Mo.

Dans une copie de tp1-graphe ouverte avec le modèle Neo4j, le `postCreateCommand` installe les 15 paquets de `.github/scripts` en une seconde, puis `npm run seed`, `npm run check` et le `LOAD CSV` de `emprunts.csv` (48 lignes) fonctionnent. `@neo4j-cypher/language-support` 2.0.0-next.38 demande Node 24.11.1 ou plus : c'est la raison du passage de l'image à Node 24 (avec Node 22, npm affichait `EBADENGINE`).

### Essai dans un vrai codespace (9 novembre 2026)

Codespace 2 cœurs créé par `nedseb` sur un dépôt privé de `IUTInfoAix-R510-2026` (`test-codespaces`), avec le modèle projet avec bonus et l'image `2026.11.1` :

- **facturation** : « Codespaces usage for this repository is paid for by nedseb ». Le réglage « User ownership » de l'organisation est actif, chaque compte paie sur son quota ;
- **création** : 60 s entre la demande et l'état « Available » ;
- **hôte** : noyau `6.8.0-1064-azure`, 2 cœurs, 7,9 Go de mémoire, 32 Go de disque dont 21 Go occupés ;
- **MongoDB** démarre, le playground de test s'exécute avec `mongosh --file` ;
- **Neo4j s'arrêtait trois secondes après son démarrage** (« Neo4j Server shutdown initiated by request » dans `neo4j.log`). Dans un codespace, la fin du `postStartCommand` termine tout le groupe de processus qui l'a lancé. `mongod --fork` sort de ce groupe, `neo4j start` non. Corrigé dans l'image `2026.11.2` : `r510-neo4j` lance `setsid -w neo4j start`. Le smoke-test reproduit la situation (étape « Neo4j survit à la fin du groupe de processus qui l'a démarré »). Ni la CLI `devcontainer` ni les workflows ne la reproduisaient ;
- avec ce correctif appliqué à la main dans le codespace : la médiathèque de tp1-graphe se charge en 7 s (43 exemplaires, 26 livres, 18 auteurs, 14 membres, 11 catégories), `LOAD CSV` lit les 48 lignes de `emprunts.csv`, MongoDB occupe 150 Mo et Neo4j 814 Mo ;
- **`LOAD CSV FROM "https://…"` fonctionne** : le codespace a accès au réseau. Sans conséquence pour l'étudiant, mais la notation ne doit pas exécuter ses requêtes avec le même accès ;
- **`gh auth status`** dans une session `gh codespace ssh` : aucun compte connecté, et `GITHUB_TOKEN` n'est pas défini dans cette session. Il reste à regarder le terminal de VS Code, où Codespaces le définit.

### À vérifier dans un vrai codespace

Rien de ce qui suit ne se teste en local. Avant la première séance, dans un codespace créé depuis une copie d'un modèle faite dans l'organisation de classe `IUTInfoAix-R510-2026` (compte étudiant de test), et non dans un compte personnel : seule cette copie montre l'effet du réglage « Codespace ownership » et du budget à 0 $ de l'organisation.

- **la création du codespace** elle-même, refusée si l'organisation paie les codespaces ;
- **le noyau de l'hôte** (`uname -r`) et le démarrage de MongoDB 9.0.4 ;
- **la machine proposée** : 2 cœurs et 8 Go, d'après le `hostRequirements` du dépôt ;
- **la durée de création** avec une image de 1,12 Go, et l'installation des extensions ;
- **les connexions préconfigurées** : « MongoDB du Codespace » dans la vue MongoDB, « Neo4j du Codespace » dans la vue Neo4j (une confirmation de confiance est attendue au premier usage, et une erreur de connexion pendant le démarrage de Neo4j), et un playground de chaque type qui s'exécute ;
- **Copilot** ne propose aucune complétion pendant la frappe, et la consigne « set a password » de la feature sshd a disparu (réglage `github.copilot.chat.codeGeneration.instructions` vide) ;
- **la mémoire** avec le serveur de langage Java ouvert sur le projet ;
- **le stockage réel** d'un codespace, image comprise, dans la page de facturation du compte de test ;
- **l'arrêt et la reprise** du codespace : les données de `~/.local/share/{mongodb,neo4j}` sont conservées et les bases redémarrent (seuls `docker stop` et `kill -9` ont été essayés) ;
- **la visibilité des ports** : la politique de l'organisation qui les limite à « privé » existe-t-elle dans l'offre Team ;
- **`gh auth status`** dans le codespace, et `gh student submit` face au `GITHUB_TOKEN` du codespace : gh student exige les droits `admin:org`, `read:org`, `repo` et `workflow` (`ghauth.RequireClient`, `cli/shared/ghauth/ghauth.go`). Le rendu retenu passe par un tag et ne dépend pas de ce point ;
- **`gh codespace ssh`** grâce à la feature sshd.

## Licence

En contribuant, vous acceptez que vos contributions soient sous licence [GPL-3.0](LICENSE).
