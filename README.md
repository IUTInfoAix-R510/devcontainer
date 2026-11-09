# Image du Codespace de R5.Real.10

Ce dépôt fabrique et publie l'image Docker de tous les Codespaces de la ressource R5.Real.10 « Nouveaux paradigmes de base de données » (BUT Informatique, 3e année, IUT d'Aix-Marseille) : TP MongoDB, TP Neo4j et projet SteamCity.

Il s'adresse aux enseignants qui maintiennent les dépôts modèles de la ressource. Les étudiants n'ont rien à faire ici : leur codespace télécharge l'image tout seul. La partie [Dépannage](#dépannage-côté-étudiant) leur est destinée, et peut être reprise dans le README de chaque TP.

## Pourquoi une image publiée

Classroom 50 crée le dépôt de chaque étudiant à partir d'un dépôt modèle, dans l'organisation de classe `IUTInfoAix-R510-2026`. Le codespace est décompté du quota personnel de l'étudiant. Les prebuilds des dépôts modèles ne s'appliquent pas à ces copies, et des prebuilds configurés sur les copies seraient facturés à l'organisation de classe, dont le budget Codespaces est à 0 $. Sans image publiée, chaque codespace reconstruirait donc tout au début de la séance (MongoDB, Neo4j, Java, Node), ou tirerait des conteneurs de service depuis Docker Hub, limité à 100 téléchargements anonymes par tranche de 6 heures et par adresse IP.

L'image est construite une fois ici, testée, puis publiée sur ghcr.io sous un tag figé. La configuration d'un dépôt de TP se réduit alors à l'image, à la machine et aux bases à démarrer. Rien ne s'installe à la création du codespace, hormis les dépendances npm propres à certains dépôts.

## Contenu de l'image

`ghcr.io/iutinfoaix-r510/r510-devcontainer:2026.11.2`, amd64 seulement (l'architecture de Codespaces).

| Outil | Version | Usage |
|---|---|---|
| MongoDB Community Server | 9.0.4 | TP1 à TP3, projet |
| mongosh | 2.14.1 | shell MongoDB |
| MongoDB Database Tools | 100.20.1 | `mongoimport`, `mongodump`… |
| Neo4j Community | 2026.10.1 | TP4, bonus du projet |
| cypher-shell | 2026.10.1 | shell Neo4j |
| Java (Eclipse Temurin) | 25.0.5 | projet SteamCity (`./mvnw`), et Neo4j |
| Node.js | 24.22.2 (LTS) | correcteurs automatiques, scripts de chargement |
| GitHub CLI | 2.103.3 | |
| gh student (Classroom 50) | v1.59.0 | secours pour les rendus, qui se font par tag `submit/…` |

Inscrits dans l'image, donc communs à tous les dépôts :

- l'utilisateur `vscode`, qui lance aussi les bases (pas de root) ;
- les extensions VS Code MongoDB, Neo4j, Java (pack) et Copilot Chat ;
- les connexions toutes prêtes dans les vues MongoDB (`mongodb://localhost:27017`) et Neo4j (`neo4j://localhost:7687`, utilisateur `neo4j`, mot de passe `mediatheque`) ;
- Copilot sans complétion automatique pendant la frappe : il ne répond que dans le chat ;
- les ports 27017, 7474 et 7687, privés, redirigés sans notification ;
- un serveur SSH, pour `gh codespace ssh`.

La machine (2 cœurs et 8 Go, celle par défaut) n'en fait pas partie : Codespaces la choisit avant de télécharger l'image, d'après le `hostRequirements` du dépôt.

## Utiliser l'image dans un dépôt de TP

Copiez le modèle qui correspond au dépôt dans son `.devcontainer/devcontainer.json` et changez son `"name"`. Si le dépôt a des dépendances npm, ajoutez leur installation en `postCreateCommand` (le modèle Neo4j le fait déjà pour les scripts de tp1-graphe, dans `.github/scripts` ; le tp2 a besoin de `npm ci` à la racine, pour ses workspaces). Supprimez le reste du dossier `.devcontainer/` (Dockerfile, `docker-compose.yml`) : l'image remplace tout.

| Dépôt | Fichier du dépôt | Modèle | Base démarrée | `postStartCommand` |
|---|---|---|---|---|
| tp1, tp2, tp3 | `.devcontainer/devcontainer.json` | [exemples/mongodb](exemples/mongodb/devcontainer.json) | MongoDB | `r510-mongo start` |
| tp4 Neo4j (nouveau dépôt, issu de tp1-graphe) | `.devcontainer/devcontainer.json` | [exemples/neo4j](exemples/neo4j/devcontainer.json) | Neo4j | `r510-neo4j start` |
| projet SteamCity | `.devcontainer/devcontainer.json` | [exemples/mongodb](exemples/mongodb/devcontainer.json) | MongoDB | `r510-mongo start` |
| projet SteamCity, bonus Neo4j | `.devcontainer/bonus-neo4j/devcontainer.json` | [exemples/projet-bonus](exemples/projet-bonus/devcontainer.json) | les deux | `r510-mongo start` et `r510-neo4j start`, en parallèle |

Par exemple, pour le TP1 :

```jsonc
{
  "name": "R5.Real.10 : TP1 MongoDB",
  "image": "ghcr.io/iutinfoaix-r510/r510-devcontainer:2026.11.2",
  "hostRequirements": { "cpus": 2, "memory": "8gb" },
  "postStartCommand": "r510-mongo start"
}
```

`postStartCommand` est rejoué à chaque démarrage du codespace : à la création, puis à chaque reprise après un arrêt. Les commandes `start` sont sans effet si la base tourne déjà.

Une base qui n'est pas démarrée ne coûte rien : Neo4j occupe environ 800 Mo au repos, MongoDB environ 150 Mo. Dans un dépôt MongoDB, l'étudiant peut quand même lancer Neo4j à la main (`r510-neo4j start`), et inversement.

**Le projet et son bonus Neo4j.** Le dépôt modèle du projet est le même pour toutes les équipes, et seules celles qui prennent le bonus doivent payer la mémoire de Neo4j. Il porte donc deux configurations : `.devcontainer/devcontainer.json` (MongoDB seul), que Codespaces prend par défaut, et `.devcontainer/bonus-neo4j/devcontainer.json` (les deux bases). Une équipe qui prend le bonus crée son codespace avec **New with options…** et choisit la seconde. Une équipe qui garde son codespace MongoDB peut aussi lancer `r510-neo4j start` depuis le dépôt, à refaire après chaque reprise du codespace.

**Dossier d'import de Neo4j.** `r510-neo4j start` relie le dossier d'import de Neo4j au dossier `data/` du dépôt. `LOAD CSV FROM "file:///emprunts.csv"` lit donc `data/emprunts.csv`, comme avec le `docker-compose.yml` de tp1-graphe. Le `data/` est cherché dans le dossier courant, puis à la racine du dépôt git qui le contient, puis dans le dossier ouvert par Codespaces : la commande marche depuis n'importe quel dossier. Si elle n'en trouve aucun, elle garde le lien actuel. Pour le bonus du projet, les CSV éventuels vont donc dans `data/` à la racine du dépôt, pas dans `graphe/`.

## Avant la première séance

Réglages de l'organisation de classe `IUTInfoAix-R510-2026`, à vérifier par un propriétaire (page **Settings**, **Codespaces**, et étape 4 du guide Classroom 50) :

- Codespaces est ouvert à tous les membres ;
- **Codespace ownership** vaut **User ownership** : avec « Organization ownership », le budget Codespaces de l'organisation, à 0 $, bloque la création de tout codespace ;
- aucune politique de type de machine n'exclut la machine 2 cœurs ;
- si l'offre le permet, une politique limite la visibilité des ports à « privé » : les bases n'ont pas d'authentification (MongoDB) ou un mot de passe connu de tous (Neo4j).

Le paquet `r510-devcontainer` est public dans l'organisation `IUTInfoAix-R510` : les codespaces, créés dans une autre organisation, le téléchargent sans authentification (voir « Publier une nouvelle image » dans [CONTRIBUTING.md](CONTRIBUTING.md)).

## Commandes des bases

Les deux commandes s'utilisent de la même façon, dans le terminal du codespace :

| Commande | Effet |
|---|---|
| `r510-mongo start`, `r510-neo4j start` | démarre la base et attend qu'elle réponde (une seconde pour MongoDB, une dizaine pour Neo4j) ; sans effet si elle tourne déjà |
| `r510-mongo stop`, `r510-neo4j stop` | l'arrête proprement (une quinzaine de secondes pour Neo4j) |
| `r510-mongo status`, `r510-neo4j status` | dit si elle tourne |
| `r510-mongo reset`, `r510-neo4j reset` | **efface toutes les données** de la base, après confirmation, puis la redémarre ; Neo4j retrouve le mot de passe `mediatheque` |
| `r510-mongo log`, `r510-neo4j log` | affiche la fin du journal |

Les données sont dans le home de `vscode` (`~/.local/share/mongodb`, `~/.local/share/neo4j`). Elles survivent à l'arrêt et à la reprise du codespace, **pas** à un « Rebuild Container », qui repart de l'image. L'arrêt du codespace n'arrête pas les bases proprement : elles sont tuées avec le conteneur, et repartent à la reprise sur leur journal (WiredTiger pour MongoDB, journaux de transactions pour Neo4j).

## Dépannage côté étudiant

**L'extension MongoDB n'arrive pas à se connecter, ou `mongosh` répond « ECONNREFUSED ».** MongoDB n'est pas démarré. Dans le terminal : `r510-mongo start`. S'il refuse de démarrer, `r510-mongo log` affiche la cause.

**L'extension Neo4j ou `cypher-shell` n'arrive pas à se connecter.** Juste après l'ouverture du codespace, Neo4j démarre encore : l'extension peut afficher une erreur de connexion pendant une quinzaine de secondes. Réessayez ensuite. Si l'erreur persiste : `r510-neo4j status`, puis `r510-neo4j start`, qui attend que Neo4j réponde. Identifiants : utilisateur `neo4j`, mot de passe `mediatheque`.

**`LOAD CSV` répond « Couldn't load the external resource ».** Le dossier d'import n'est pas relié au `data/` du dépôt. Dans le terminal, depuis n'importe quel dossier du dépôt : `r510-neo4j start`. La commande relie le dossier même si Neo4j tourne déjà, et affiche le dossier relié.

**Neo4j Browser (http://localhost:7474) ne s'ouvre pas ou ne se connecte pas.** C'est normal dans Codespaces : il ne passe pas par le tunnel du codespace. Utilisez l'extension VS Code Neo4j, qui affiche aussi les résultats en graphe.

**Ma base est dans un état incohérent.** `r510-mongo reset` ou `r510-neo4j reset` repartent d'une base vide ; rechargez ensuite les données du TP (script de chargement ou `npm run seed` selon le TP).

**Mes données ont disparu.** Un « Rebuild Container » repart de l'image et efface les bases. Votre code, lui, est dans `/workspaces` et n'est pas touché.

**Rendre son travail.** Suivez la partie « Rendre son travail » de l'énoncé : le rendu est un tag `submit/…` poussé depuis le terminal. `gh student` est installé dans l'image, en secours. Ne lancez pas `gh student login` dans le codespace sans consigne de vos enseignants : il y enregistrerait un jeton qui a le droit `admin:org`.

**Ne rendez pas les ports publics.** Dans l'onglet **Ports**, laissez 27017, 7474 et 7687 en « Private » : MongoDB n'a pas de mot de passe, et celui de Neo4j est connu de tous.

**Mon quota de stockage Codespaces est presque épuisé.** Un codespace arrêté occupe toujours du stockage, et son image compte dedans. Le quota gratuit est de 15 Go-mois avec un compte GitHub Free, 20 avec GitHub Pro ([facturation de Codespaces](https://docs.github.com/en/billing/concepts/product-billing/github-codespaces)). Une fois un TP rendu, poussez votre travail (`git push`), puis supprimez son codespace : sur github.com/codespaces, menu **…** du codespace, **Delete**.

## Maintenance

Construire, tester, publier une nouvelle image et changer une version : voir [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

[GPL-3.0](LICENSE), comme les autres dépôts de R5.Real.10.
