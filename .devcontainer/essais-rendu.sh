#!/bin/sh
# Essais de r510-sauver, r510-rendre, r510-verifier et r510-recharger, sans réseau : chaque scénario clone un
# dépôt nu local qui joue le rôle de GitHub. Le nom du dépôt nu décide du type
# de dépôt vu par r510-rendre : r510-tp1-essai.git pour un TP,
# r510-projet-group-1.git pour le projet.
#
# Lancé par smoke-test.sh dans le conteneur (commandes de /usr/local/bin), et
# en local, sans l'image, sur les sources :
#   PATH="$PWD/.devcontainer/source:$PATH" sh .devcontainer/essais-rendu.sh
#
# N'écrit que dans un dossier temporaire, supprimé à la fin. La configuration
# git de l'utilisateur est ignorée (GIT_CONFIG_GLOBAL), pour qu'une signature
# des commits ou un hook global ne fausse pas les essais.
set -eu

for c in git r510-sauver r510-rendre r510-verifier r510-recharger r510-integrer; do
    command -v "$c" > /dev/null || { echo "✗ $c introuvable dans le PATH" >&2; exit 2; }
done

ESSAI=$(mktemp -d)
trap 'rm -rf "$ESSAI"' EXIT
export GIT_CONFIG_GLOBAL="$ESSAI/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name essai
git config --global user.email essai@exemple.fr
git config --global init.defaultBranch main
git config --global advice.detachedHead false
unset GITHUB_REPOSITORY || true

SORTIE="$ESSAI/sortie.txt"
n=0
ok() { n=$((n + 1)); printf '  ✓ %s\n' "$1"; }
echec() {
    printf '✗ %s\n' "$1" >&2
    [ -s "$SORTIE" ] && { echo "--- sortie de la commande :" >&2; cat "$SORTIE" >&2; echo "---" >&2; }
    exit 1
}
# lance CMD… : exécute la commande, sortie complète dans $SORTIE ; renvoie son code.
lance() { "$@" > "$SORTIE" 2>&1; }
contient() { grep -qF -- "$1" "$SORTIE"; }
simple_push() { grep -qx -- "→ git push" "$SORTIE"; }
tags_distants() { git ls-remote --tags origin 'refs/tags/submit/*' | grep -vc '\^{}$' || true; }

# nouveau_depot NOM_DU_DEPOT_NU DOSSIER : crée le dépôt nu, un clone avec un
# premier commit poussé sur main, et s'y place.
nouveau_depot() {
    git init -q --bare "$ESSAI/$1"
    git clone -q "$ESSAI/$1" "$ESSAI/$2" 2> /dev/null
    cd "$ESSAI/$2"
    echo a > f && git add f && git commit -qm init && git push -q -u origin main 2> /dev/null
}

# ------------------------------------------------------------------ TP
echo "→ TP (dépôt r510-tp1-essai)"
nouveau_depot r510-tp1-essai.git tp

lance r510-sauver --help || echec "r510-sauver --help"
contient "Ce n'est PAS un rendu" || echec "r510-sauver --help n'annonce pas que ce n'est pas un rendu"
lance r510-rendre --help || echec "r510-rendre --help"
contient "git tag submit/" || echec "r510-rendre --help ne montre pas le tag submit/"
ok "aide des deux commandes"

echo b >> f
lance r510-sauver "essai main" || echec "r510-sauver sur main"
simple_push || echec "r510-sauver sur main ne fait pas un simple git push"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || echec "r510-sauver n'a pas poussé main"
[ "$(git log -1 --format=%s)" = "essai main" ] || echec "message du commit de r510-sauver"
lance r510-sauver || echec "r510-sauver sans modification"
contient "rien de nouveau" || echec "r510-sauver sans modification n'annonce pas « rien de nouveau »"
ok "r510-sauver sur main : add, commit, push"

git switch -q -c feat/essai
echo c >> f
lance r510-sauver "essai branche" || echec "r510-sauver sur une nouvelle branche sans branche amont"
contient "→ git push -u origin feat/essai" || echec "premier push d'une nouvelle branche sans -u"
contient "branche feat/essai" || echec "r510-sauver ne nomme pas la branche sauvegardée"
git ls-remote --heads origin feat/essai | grep -q . || echec "la branche n'est pas sur le dépôt distant"
[ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feat/essai" ] || echec "la branche amont n'est pas réglée"
echo d >> f
lance r510-sauver || echec "second r510-sauver sur la branche"
simple_push || echec "second r510-sauver : -u alors que la branche amont existe"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/feat/essai)" ] || echec "second r510-sauver n'a pas poussé la branche"
ok "r510-sauver sur une nouvelle branche : push -u la première fois, push ensuite"

lance r510-rendre --oui --sans-check && echec "r510-rendre accepté hors de main"
contient "le rendu se fait depuis main" || echec "r510-rendre hors de main : message"
git switch -q --detach HEAD
lance r510-sauver && echec "r510-sauver accepté en HEAD détachée"
contient "HEAD détachée" || echec "r510-sauver en HEAD détachée : message"
git switch -q main
ok "refus : r510-rendre hors de main, r510-sauver en HEAD détachée"

echo e >> f
lance r510-rendre < /dev/null && echec "r510-rendre accepté sans terminal ni --oui"
contient "Pas de terminal interactif" || echec "r510-rendre sans terminal : message"
[ "$(tags_distants)" = 0 ] || echec "r510-rendre sans terminal a poussé un tag"
ok "refus : r510-rendre sans terminal interactif ni --oui"

if command -v npm > /dev/null; then
    printf '{ "scripts": { "check": "echo Score : 7/10", "seed": "echo Recharge" } }\n' > package.json
    mkdir -p sous-dossier
    (cd sous-dossier && lance r510-verifier) || echec "r510-verifier depuis un sous-dossier"
    contient "Score : 7/10" || echec "r510-verifier n'affiche pas le score"
    contient "npm" && echec "r510-verifier montre npm"
    lance r510-verifier --sortie r.json && echec "r510-verifier accepte un argument"
    lance r510-recharger || echec "r510-recharger"
    contient "Recharge" || echec "r510-recharger ne lance pas le chargement"
    lance r510-recharger --avant 12 || echec "r510-recharger --avant 12"
    contient "Recharge --avant 12" || echec "r510-recharger ne transmet pas --avant"
    lance r510-recharger 12 && echec "r510-recharger accepte un numéro sans --avant"
    lance r510-recharger --avant && echec "r510-recharger accepte --avant sans numéro"
    rmdir sous-dossier
    ok "r510-verifier et r510-recharger : sous-dossier, arguments, npm invisible"
    git add package.json && git commit -qm "check factice"
    lance r510-rendre --oui || echec "r510-rendre --oui (TP)"
    contient "npm" && echec "r510-rendre montre npm"
    contient "Score : 7/10 (indicatif)" || echec "le score indicatif de r510-verifier n'est pas affiché"
else
    lance r510-rendre --oui --sans-check || echec "r510-rendre --oui (TP)"
    echo "  (npm absent : r510-verifier non essayé)"
fi
contient "Ce sera votre rendu n° 1 (trois au plus par TP)." || echec "annonce du rendu n° 1 d'un TP"
contient "La note apparaît dans 2 à 5 minutes" || echec "message final d'un TP"
contient "accusé de réception" && echec "message du projet dans un TP"
[ "$(tags_distants)" = 1 ] || echec "le tag submit/ n'est pas sur le dépôt distant"
git diff --quiet origin/main || echec "le commit « rendu » n'est pas poussé"
ok "r510-rendre (TP) : rendu n° 1, score indicatif, tag poussé"

git tag submit/20000101-000002 && git tag submit/20000101-000003
git push -q origin submit/20000101-000002 submit/20000101-000003 2> /dev/null
sleep 1    # deux rendus dans la même seconde auraient le même tag
lance r510-rendre --oui --sans-check || echec "quatrième r510-rendre (TP)"
contient "Ce serait votre rendu n° 4, alors que la consigne est de trois rendus au plus par TP." \
    || echec "pas d'avertissement au quatrième rendu d'un TP"
ok "r510-rendre (TP) : avertissement au-delà de trois rendus"

# GitHub injoignable : le rang vient des tags locaux (4 ici).
git remote set-url origin "$ESSAI/absent.git"
lance r510-rendre < /dev/null && echec "r510-rendre accepté sans terminal (origin injoignable)"
contient "Ce serait votre rendu n° 5" || echec "sans GitHub, le rang ne vient pas des tags locaux"
git remote set-url origin "$ESSAI/r510-tp1-essai.git"
ok "r510-rendre : rang compté sur les tags locaux si GitHub ne répond pas"

if command -v script > /dev/null; then
    printf 'n\n' | script -qec "r510-rendre --sans-check" /dev/null > "$SORTIE" 2>&1 || echec "r510-rendre interactif"
    contient "Rien n'a été rendu." || echec "réponse « n » à la confirmation non respectée"
    [ "$(tags_distants)" = 4 ] || echec "un tag a été poussé malgré la réponse « n »"
    ok "r510-rendre interactif : la réponse « n » ne rend rien"
fi

# ------------------------------------------------------ mise à jour du TP
echo "→ Mise à jour du TP poussée par l'équipe enseignante"
nouveau_depot r510-tp1-maj.git maj
mkdir -p .github data .devcontainer
printf 'bouge .github\nbouge .devcontainer\nbouge data\nbouge enonce\netudiant reponses\nclassroom50 .github/autograde.yaml\n' > .github/fichiers-du-tp.txt
printf 'un\ndeux\ntrois\n' > enonce; echo r0 > reponses; echo d > data/d; echo c50 > .github/autograde.yaml; echo v1 > .github/ancien
git add -A && git commit -qm TP && git push -q 2> /dev/null
git clone -q "$ESSAI/r510-tp1-maj.git" "$ESSAI/enseignant" 2> /dev/null
# enseignant CMD : un commit de l'équipe enseignante, poussé sur main.
enseignant() { (cd "$ESSAI/enseignant" && git pull -q --no-edit 2> /dev/null && sh -c "$1" && git add -A && git commit -qm "Mise à jour" && git push -q 2> /dev/null); }

lance r510-integrer || echec "r510-integrer sans mise à jour"
[ -s "$SORTIE" ] && echec "r510-integrer parle alors qu'il n'y a rien à intégrer"
ok "r510-integrer : muet sans mise à jour"

enseignant "echo v2 > .github/nouveau; rm .github/ancien"
echo r1 >> reponses
lance r510-integrer --souple || echec "intégration au démarrage"
[ -f .github/nouveau ] && [ ! -e .github/ancien ] || echec "ajout ou suppression non intégrés"
grep -qx r1 reponses || echec "réponse non enregistrée perdue au démarrage"
git diff --quiet -- reponses && echec "réponse non enregistrée commitée au démarrage"
ok "r510-integrer au démarrage : ajout, suppression, réponse non enregistrée gardée"

enseignant "echo quatre >> enonce"
lance r510-sauver || echec "r510-sauver alors que l'enseignant a mis à jour"
git show origin/main:reponses | grep -qx r1 || echec "réponse absente de GitHub"
git show origin/main:enonce | grep -qx quatre || echec "mise à jour perdue par r510-sauver"
contient "Mise à jour du TP" || echec "r510-sauver n'annonce pas la mise à jour"
ok "r510-sauver : intègre puis pousse"

enseignant "sed -i 's/^deux\$/deux corrigé/' enonce"
echo brouillon >> enonce
lance r510-integrer --souple || echec "fichier qui bouge modifié localement"
grep -qx "deux corrigé" enonce || echec "la version enseignante ne l'emporte pas"
grep -rqx brouillon .git/r510-sauvegarde || echec "modification locale non copiée avant remplacement"
ok "fichier qui bouge modifié : version enseignante, copie gardée"

sed -i 's/^un$/un bricolé/' enonce && git commit -qam bricolage
enseignant "sed -i 's/^un\$/un officiel/' enonce"
lance r510-integrer || echec "conflit sur un fichier qui bouge"
grep -qx "un officiel" enonce || echec "conflit : la version enseignante ne l'emporte pas"
git log --format=%s | grep -qx bricolage || echec "conflit : historique de l'étudiant perdu"
ok "conflit commité sur un fichier qui bouge : résolu, historique gardé"

mkdir -p data; echo local > data/nouveau
enseignant "echo officiel > data/nouveau"
lance r510-integrer || echec "fichier non suivi en collision"
grep -qx officiel data/nouveau || echec "collision : version enseignante absente"
grep -rqx local .git/r510-sauvegarde || echec "collision : copie absente"
contient "r510-recharger" || echec "données changées non annoncées"
ok "fichier non suivi en collision, données changées annoncées"

enseignant "mkdir -p .devcontainer; echo image > .devcontainer/devcontainer.json"
lance r510-integrer || echec "changement d'environnement"
contient "Rebuild Container" || echec "reconstruction non annoncée"
ok "environnement changé : reconstruction annoncée"

enseignant "echo verifie >> data/d"
echo r2 >> reponses
lance r510-rendre --oui --sans-check || echec "r510-rendre alors que l'enseignant a mis à jour"
t=$(git tag -l 'submit/*' | tail -1)
git show "$t:reponses" | grep -qx r2 || echec "le rendu n'a pas la réponse"
git show "$t:data/d" | grep -qx verifie || echec "le rendu n'a pas la mise à jour"
[ "$(tags_distants)" = 1 ] || echec "rendu non poussé"
ok "r510-rendre : intègre, pousse, tag complet"

enseignant "echo second-codespace > reponses"
echo ici > reponses
lance r510-integrer --souple || echec "--souple a fait échouer l'appelant"
grep -qx ici reponses || echec "réponse locale écrasée au démarrage"
lance r510-sauver && echec "conflit de réponses accepté"
contient "rien n'est perdu" || echec "conflit de réponses : message"
contient "Votre travail est enregistré. Pour terminer : git pull" || echec "conflit : la consigne renvoie à la commande qui vient d'échouer"
grep -qx ici reponses || echec "réponse locale écrasée"
git rev-parse -q --verify MERGE_HEAD > /dev/null && echec "fusion laissée en cours"
git show origin/main:reponses | grep -qx second-codespace || echec "réponse de GitHub écrasée"
sleep 1
lance r510-rendre --oui --sans-check && echec "rendu accepté malgré un conflit de réponses"
[ "$(tags_distants)" = 1 ] || echec "tag poussé malgré un conflit de réponses"
ok "conflit de réponses : arrêt net, rien de perdu, rien de rendu"

contient "git pull --no-rebase" || echec "conflit de réponses : aucune issue indiquée"
lance git pull --no-rebase --no-edit && echec "le pull devait partir en conflit"
echo "travail pendant la fusion" >> reponses
lance r510-integrer --souple || echec "fusion en cours : --souple a échoué"
git rev-parse -q --verify MERGE_HEAD > /dev/null || echec "fusion de l'étudiant annulée"
grep -qx "travail pendant la fusion" reponses || echec "travail écrit pendant la fusion perdu"
lance r510-sauver && echec "marqueurs de conflit sauvegardés"
git show origin/main:reponses | grep -q '^<<<<<<<' && echec "marqueurs de conflit poussés"
git add reponses
lance r510-sauver && echec "marqueurs de conflit déjà indexés sauvegardés"
ok "fusion de l'étudiant : jamais annulée, marqueurs jamais poussés"

git show HEAD:reponses > reponses
lance r510-sauver || echec "fusion où l'on garde sa version : pas de sortie"
git rev-parse -q --verify MERGE_HEAD > /dev/null && echec "fusion non conclue"
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || echec "fusion conclue mais non poussée"
grep -qx ici reponses || echec "version gardée perdue"
ok "fusion où l'on garde sa version : conclue et poussée"

mkdir -p hooks-essai && printf '#!/bin/sh\nexit 1\n' > hooks-essai/pre-commit && chmod 755 hooks-essai/pre-commit
echo perdu >> reponses
git config core.hooksPath "$PWD/hooks-essai"
lance r510-sauver && echec "commit impossible annoncé comme sauvegardé"
contient "Commit impossible" || echec "commit impossible : message"
lance r510-rendre --oui --sans-check && echec "commit impossible annoncé comme rendu"
[ "$(tags_distants)" = 1 ] || echec "tag poussé alors que le commit a échoué"
git config --unset core.hooksPath
rm hooks-essai/pre-commit && rmdir hooks-essai
lance r510-sauver || echec "sauvegarde après correction de la cause"
ok "commit impossible : jamais de faux succès, aucun tag"

(flock 7; sleep 3) 7> "$(git rev-parse --git-path r510-integrer.lock)" &
sleep 0.5
echo "sous verrou" >> reponses
lance r510-sauver || echec "r510-sauver pendant une intégration"
wait
git show origin/main:reponses | grep -qx "sous verrou" || echec "réponse perdue sous verrou"
ok "r510-sauver attend une intégration en cours"

if command -v npm > /dev/null; then
    printf '{ "scripts": { "check": "echo MongoDB éteint; exit 3" } }\n' > package.json
    git add package.json && git commit -qm "check en panne" && git push -q 2> /dev/null
    sleep 1
    lance r510-rendre --oui || echec "r510-rendre muet quand r510-verifier n'a pas de score"
    contient "MongoDB éteint" || echec "cause de l'absence de score non affichée"
    [ "$(tags_distants)" = 2 ] || echec "rendu sans score non poussé"
    ok "sans score : cause affichée, rendu possible"
fi

mkdir -p data/lot && echo "dossier local" > data/lot/notes
enseignant "echo officiel > data/lot"
lance r510-integrer || echec "dossier local là où arrive un fichier"
grep -qx officiel data/lot || echec "fichier officiel absent"
grep -rqx "dossier local" .git/r510-sauvegarde || echec "dossier local non copié"
ok "collision dossier et fichier : copie puis intégration"

echo "fichier local" > data/sous
enseignant "mkdir -p data/sous; echo officiel > data/sous/x"
lance r510-integrer || echec "fichier local là où arrive un dossier"
grep -qx officiel data/sous/x || echec "dossier officiel absent"
grep -rqx "fichier local" .git/r510-sauvegarde || echec "fichier local non copié"
ok "collision fichier et dossier : copie puis intégration"

: > .git/index.lock
enseignant "echo encore >> enonce"
lance r510-integrer && echec "index.lock ignoré"
contient "index.lock" || echec "index.lock : message"
rm .git/index.lock
lance r510-integrer || echec "intégration après retrait de index.lock"
ok "index.lock abandonné : message juste"

mkdir -p .git/rebase-merge
lance r510-sauver && echec "rebase en cours ignoré"
contient "git rebase --abort" || echec "rebase en cours : message"
rmdir .git/rebase-merge
ok "rebase en cours : issue indiquée"

git remote set-url origin "$ESSAI/absent.git"
lance r510-integrer || echec "GitHub injoignable : r510-integrer échoue"
contient "GitHub ne répond pas" || echec "GitHub injoignable : message"
ok "GitHub injoignable : sans blocage"

# ------------------------------------------------------------------ projet
echo "→ Projet (dépôt r510-projet-group-1)"
nouveau_depot r510-projet-group-1.git projet

lance r510-rendre --oui --sans-check || echec "r510-rendre --oui (projet)"
contient "Ce sera le rendu n° 1 sur 5 de votre équipe" || echec "annonce du rendu n° 1 du projet"
contient "ce n'est pas une note" || echec "le projet n'annonce pas un accusé de réception"
contient "trois" && echec "règle des TP (trois rendus) annoncée pour le projet"
contient "La note apparaît" && echec "« la note apparaît » annoncé pour le projet"
[ "$(tags_distants)" = 1 ] || echec "le tag submit/ du projet n'est pas sur le dépôt distant"
ok "r510-rendre (projet) : rendu n° 1 sur 5, accusé de réception"

# Un coéquipier pousse trois rendus depuis son propre clone : ils comptent.
git clone -q "$ESSAI/r510-projet-group-1.git" "$ESSAI/coequipier" 2> /dev/null
(
    cd "$ESSAI/coequipier"
    for i in 2 3 4; do git tag "submit/20000101-00000$i"; done
    git push -q origin --tags 2> /dev/null
)
sleep 1
lance r510-rendre --oui --sans-check || echec "cinquième r510-rendre (projet)"
contient "Ce sera le rendu n° 5 sur 5 de votre équipe" || echec "les rendus du coéquipier ne sont pas comptés"
contient "un rendu suivant serait ignoré" || echec "pas d'avertissement au cinquième rendu"
ok "r510-rendre (projet) : rendus des coéquipiers comptés, avertissement au cinquième"

echo g >> f
lance r510-rendre < /dev/null && echec "sixième r510-rendre accepté sans terminal"
contient "Seuls les cinq premiers comptent" || echec "pas d'avertissement avant un sixième rendu"
contient "rendu n° 6 ne serait pas pris en compte" || echec "le sixième rendu n'est pas annoncé comme ignoré"
[ "$(tags_distants)" = 5 ] || echec "un sixième tag a été poussé sans confirmation"
ok "r510-rendre (projet) : avertissement avant un sixième rendu"

# main a avancé sur GitHub (une Pull Request fusionnée) : le push est refusé,
# rien n'est rendu, et la commande dit de faire git pull.
(
    cd "$ESSAI/coequipier"
    git pull -q 2> /dev/null && echo pr > pr.txt && git add pr.txt && git commit -qm "PR fusionnée" && git push -q 2> /dev/null
)
sleep 1
lance r510-rendre --oui --sans-check && echec "r510-rendre accepté alors que main a avancé sur GitHub"
contient "git pull" || echec "pas de conseil « git pull » quand main a avancé"
[ "$(tags_distants)" = 5 ] || echec "un tag a été poussé alors que le push de main a échoué"
git pull -q --no-rebase --no-edit 2> /dev/null
lance r510-rendre --oui --sans-check || echec "sixième r510-rendre --oui (projet)"
contient "Il dépasse les cinq rendus : il ne compte pas." || echec "message final d'un sixième rendu"
ok "r510-rendre (projet) : main en retard refusé avec conseil, sixième rendu signalé"

# Détection par les fichiers : dépôt renommé, ou dépôt modèle du projet.
nouveau_depot depot-renomme.git renomme
mkdir -p .github/classroom/issues && echo "# Intro" > .github/classroom/issues/00-intro.md
lance r510-rendre < /dev/null || true
contient "sur 5 de votre équipe" || echec "projet non reconnu à .github/classroom/issues"
rm -rf .github
echo 'pseudonyme: "Essai"' > quetes.yml
lance r510-rendre < /dev/null || true
contient "sur 5 de votre équipe" || echec "projet non reconnu à quetes.yml"
rm quetes.yml
lance r510-rendre < /dev/null || true
contient "(trois au plus par TP)" || echec "dépôt sans marque du projet pris pour le projet"
ok "détection du projet par ses fichiers, à défaut du nom du dépôt"

printf '\n✓ r510-sauver et r510-rendre : %s essais réussis\n' "$n"
