#!/bin/bash
# 
# Migrate the commit history of archived easyconfigs from a local
# easybuild-easyconfigs repo to another target repo.
# - archived easyconfigs are taken from the '__archive__' folder in the
#   local easybuild-easyconfigs repo
# - migrated easyconfigs are placed in the destination repo keeping the folder
#   structure, that is alphabetical directory structure under
#   'easybuild/easyconfigs/__archive__'
# - commit history of each migrated file is copied over to destination repo in
#   a new branch ready to be PRd
#

set -eu

VERSION="1.0"
LOG_LEVEL="info"
EASYCONFIGS_REPO="easybuild-easyconfigs"
ARCHIVE_REPO="easybuild-easyconfigs-archive"

error_exit() {
    # Print error message and exit
    error_msg="ERROR: $1"
    echo "$error_msg"
    exit 1
}

display_help() {
    # Print usage help
    echo "Migrate commit history of archived easyconfigs into another repository"
    echo "Usage: archive-migration.sh [-hvd] [-a ARCHIVE_REPO] [-e EASYCONFIGS_REPO] ARCHIVE_BRANCH"
    echo "  PATH: path to local directory storing the PDB"
    echo "  -h: print this help message"
    echo "  -v: print version"
    echo "  -d: set verbosity to debug level"
    echo "  -a: path to easybuild-easyconfigs-archive repo (default: ${ARCHIVE_REPO})"
    echo "  -e: path to easybuild-easyconfigs repo (default: ${EASYCONFIGS_REPO})"
}

# Parse optional arguments
while getopts 'hvda:e:' opt; do
    case "${opt}" in
        a)  # [-a] set archive repo
            ARCHIVE_REPO=$OPTARG
            ;;
        e)  # [-e] set easyconfig repo
            EASYCONFIGS_REPO=$OPTARG
            ;;
        v)  # [-v] version
            echo "pdb-sync v${VERSION}"
            exit 0
            ;;
        d)  # [-d] debug level
            LOG_LEVEL="debug"
            ;;
        h)  # [-h] help
            display_help
            exit 0
            ;;
        *) # Unknown argument
            display_help
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

# Parse positional argument
if [ $# -eq 0 ]; then
    echo "ERROR: Missing name of ARCHIVE_BRANCH to migrate commit history of archive"
    display_help
    exit 1
fi
ARCHIVE_BRANCH="${1}"

[ -d "$ARCHIVE_REPO" ] || error_exit "path to local easybuild-easyconfigs-archive repo does not exist: $ARCHIVE_REPO"
ARCHIVE_REPO="$(realpath $ARCHIVE_REPO)"
[ "$LOG_LEVEL" = "debug" ] && echo "-- absolute path to target easybuild-easyconfigs-archive repo: $ARCHIVE_REPO"

[ -d "$EASYCONFIGS_REPO" ] || error_exit "path to local easybuild-easyconfigs repo does not exist: $EASYCONFIGS_REPO"
EASYCONFIGS_REPO="$(realpath $EASYCONFIGS_REPO)"
[ "$LOG_LEVEL" = "debug" ] && echo "-- absolute path to target easybuild-easyconfigs repo: $EASYCONFIGS_REPO"

[ "$LOG_LEVEL" = "debug" ] && set -x

# clone the target branch of the easybuild-easyconfigs repo
PRUNE_DIR=$(mktemp -d)
PRUNE_REPO="$PRUNE_DIR/$(basename $EASYCONFIGS_REPO)"
echo "== Copying easybuild-easyconfigs repo ($EASYCONFIGS_REPO) into temp directory ($PRUNE_DIR)"
cp -r "$EASYCONFIGS_REPO" "$PRUNE_DIR/" || error_exit "failed to copy local easybuild-easyconfigs repo"
cd "$PRUNE_REPO"
echo "== Checking out archive branch ($ARCHIVE_BRANCH)"
git switch "$ARCHIVE_BRANCH" || error_exit "archive branch ($ARCHIVE_BRANCH) does not exist in easybuild-easyconfigs repo"
[ "$LOG_LEVEL" = "debug" ] && git status

# generate a list of glob patterns that match all files currently under `__archive__`
# in any path the might have been in their lifetime in the repo
# (this serves to catch all commits related to those files, even before their archival)
find easybuild/easyconfigs/__archive__/ -type f -exec basename {} \; | sed 's|^|glob:easybuild/easyconfigs/*/*/|' > "$PRUNE_DIR/prune.list"
ARCHIVES_COUNT="$(wc -l < $PRUNE_DIR/prune.list)"
# filter the repo using the previous list
echo "== Filtering commit history of $ARCHIVES_COUNT files under '__archive__'"
git filter-repo --force --paths-from-file "$PRUNE_DIR/prune.list"

# switch to easybuild-easyconfigs-archive repo
cd "$ARCHIVE_REPO" || error_exit "failed to change dir to archive repo"
echo "== Creating new branch ($ARCHIVE_BRANCH) in easybuild-easyconfigs-archive repo"
git branch "$ARCHIVE_BRANCH"
git switch "$ARCHIVE_BRANCH"
[ "$LOG_LEVEL" = "debug" ] && git status
echo "== Copying commit history into easybuild-easyconfigs-archive repo"
git remote add prune-repo "$PRUNE_REPO"
git pull --allow-unrelated-histories --strategy-option=theirs --no-commit prune-repo "$ARCHIVE_BRANCH"
git commit -m "Archive commit history of $ARCHIVES_COUNT files in easybuild-easyconfigs"
git remote rm prune-repo
