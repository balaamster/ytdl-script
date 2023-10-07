#!/bin/bash

readonly USAGE="Usage:
    $(basename $0) -u <video_link> [-a <audio_format>] [-v <vidio_format>] [-o <output_directory>]

Env variables:
	YTDL_OUTDIR: defines output directory
"

readonly DEFAULT_OUTDIR="$HOME/Downloads"

readonly -A EXTS='(
	[251]=opus
	[250]=opus
	[249]=opus
	[140]=m4a
	[139]=m4a
)'

readonly -a DEPENDENCY='(
	yt-dlp
	ffmpeg
)'

### COLORS
readonly NoC="$(echo -e "\033[0m")"			# Color Reset
readonly Yellow="$(echo -e "\033[1;33m")"		# Yellow
###


function error {
    if [ ${#@} -ne 0 ]; then
        for message in "$@"; do
            echo -e "$message" >&2
        done
    fi
    exit 1
}


function show_msg () {
	echo -e "$@"
	read -p 'press [ENTER] to continue...'
}


function check_deps () {
        local -i result
        for i in "$@"; do
                if [ -z "$(which $i)" ]; then
                    echo "There no required tool: $i"
                    [ -v result ] || result=1
                fi
        done
        return ${result:-0}
}


function sel_fmt () {
	# $1 - selected format, $2 - format list, $3 - prompt
	# format list - string of space separated format IDs in square brackets, like: "[251] [140]"  
	if ! grep -q "\[$1\]" <<<"$2"; then
		echo "!!! Wrong selection: "$1" !!!"
		read -n3 -p "$3" ask_fmt
		return 1
	fi
}


function normalize_url {
    [ $# -ge 1 ] || error 'There no url to process'
    echo "$1" | egrep -q '^(http.?://)?www.youtube.com/watch\?v=.{11}' || error "Wrong URL:\n$1"
    echo "${1%%&*}"
}

function check_opt {
  [[ "$2" == -* ]] && error "Key -$1 must have an argument"
}


### exit if there no args
[ $# -eq 0 ] && error "$USAGE"

### parse args
while getopts ':u:a:v:o:' current_option; do
	case "$current_option" in
		u)	check_opt "$current_option" "$OPTARG"
			url="$(normalize_url "$OPTARG")"
			[ -z "$url" ] && error
			;;
		a) 	check_opt "$current_option" "$OPTARG"
			a_fmt="$OPTARG"
			;;
		v) 	check_opt "$current_option" "$OPTARG"
			v_fmt="$OPTARG"
			;;
		o)	check_opt "$current_option" "$OPTARG"
			outdir="$OPTARG"
			;;
		:) error "Key -$OPTARG must have an argument";;
		*) error "Wrong key: -$OPTARG" "$USAGE";;
	esac
done
shift $(($OPTIND - 1))

### chech for required utilities
check_deps "${DEPENDENCY[@]}" || error

fnm=$(yt-dlp --no-playlist --get-filename --encoding=cp866 -o '%(title)s_-%(upload_date)s' "$url"|sed  's/ /_/g'|iconv -c -f CP866 -t UTF-8)
echo "=== Filename is:"
echo "=== $fnm"

fmt_tbl=$(yt-dlp --no-playlist -F "$url")

afmt_lst=$(echo "$fmt_tbl"| grep -E 'audio only' | awk '$1 ~ /^[0-9]+/ {print "["$1"] "} END {print "[0]"}')
vfmt_lst=$(echo "$fmt_tbl"| grep -E 'video only|mp4v|av01|avc1|vp0?9' | awk '$1 ~ /^[0-9]+/ {print "["$1"] "} END {print "[0]"}')

echo -e "$fmt_tbl" | sed -e "1,5 d" -e 's/^\([0-9]\+\)/'${Yellow}'\1'${NoC}'/'

# Check video format
while ! sel_fmt "${v_fmt:-NoFormat}" "$vfmt_lst" "Video ID:"; do
	v_fmt="$ask_fmt"
done
unset ask_fmt
# Check audio format
while ! sel_fmt "${a_fmt:-NoFormat}" "$afmt_lst" "Audio ID:"; do
	a_fmt="$ask_fmt"
done

# If outdir not set with -o argument, then get outdir from env variable YTDL_OUTDIR or substitute default 
[ -v outdir ] || outdir="${YTDL_OUTDIR:="$DEFAULT_OUTDIR"}"
[ -d $outdir ] || error "!!! $outdir not exists !!!"
cd "$outdir"

#echo "v_fmt=$v_fmt"
#echo "a_fmt=$a_fmt"
#echo "Output dir: $outdir"
#error __Testing__

declare -a dl_lst
# AUDIO
[[ $a_fmt != 0 ]] && dl_lst+=("yt-dlp -f $a_fmt -o \"$fnm.aud\" \"$url\"")
# VIDEO
[[ $v_fmt != 0 ]] && dl_lst+=("yt-dlp -f $v_fmt -o \"$fnm.vid\" \"$url\" --sub-lang en,ru --write-sub")

#printf '%s\0' "${dl_lst[@]}" | parallel -0 -t
printf '%s\0' "${dl_lst[@]}" | xargs -P 2 -0 -t -i sh -c '{}'

if [[ $v_fmt != 0 ]]; then
	ffmpeg -loglevel 24 -hide_banner -i "$fnm.vid" -i "$fnm.aud" -c copy "$fnm.mkv" && rm -f "$fnm.vid" "$fnm.aud"
else
	ffmpeg -loglevel 24 -hide_banner -i "$fnm.aud" -c copy "$fnm.${EXTS[$a_fmt]}" && rm -f "$fnm.aud"
fi
