set -o nounset -o errexit -o pipefail
set -x

if [[ $# -eq 0 ]]; then
    printf 'usage: %s REPO_1 <REPO_2 .. REPO_N>\n' "${0##*/}"
    exit 2
fi

for repo; do
    conf="/etc/cvmfs/repositories.d/$repo/server.conf"
    reflog="/var/spool/cvmfs/$repo/reflog.chksum"
    if [[ ! -f "$reflog" ]]; then
        if [[ -f "$conf" ]]; then
            source "$conf"
            CURL_EXTRA_FLGAS=""
            if [[ ! -z "$CVMFS_SERVER_PROXY" ]]; then
                CURL_EXTRA_FLGAS="-x $CVMFS_SERVER_PROXY"
            fi
            tmpfile=$(mktemp /tmp/reflog.chksum.XXXXXX)
            trap '[[ ! -f "$reflog" ]] && printf "%040x" "0" > "$reflog"; rm -f -- "$tmpfile"; exit 0' INT TERM HUP EXIT
            # --fail is necessary to return an empty body in case of 404
            curl --fail -s $CURL_EXTRA_FLGAS "$CVMFS_STRATUM0/.cvmfsreflog" | sha1sum | cut -d' ' -f1 > "$tmpfile"
            install -m0644 -o "$CVMFS_USER" "$tmpfile" "$reflog"
        fi
    fi
done

