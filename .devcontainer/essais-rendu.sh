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

for c in git r510-sauver r510-rendre r510-verifier r510-recharger; do
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
