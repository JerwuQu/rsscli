#!/bin/sh
set -e
DATA_DIR=${RSSCLI_DIR:="$HOME/.rsscli"}
FEEDS_FILE="$DATA_DIR/feeds"
TAB='	'

mkdir -p "$DATA_DIR"

format_date() { # input-date-format date
	# TODO: The `date` util varies greatly depending on system.
	#       The busybox variant can't take timezone into account when parsing
	#       a custom date format, so an alternative solution is needed for accurate time.
	set -e
	if date --help 2>&1 | grep -q GNU; then
		date -ud "$2" +'%F %T'
	else
		date -ud "$2" -D "$1" +'%F %T'
	fi
}
format_feed_dates() { # input-date-format < feed-items
	while read -r line; do
		echo "$(format_date "$1" "$(echo "$line" | cut -f 1)")$TAB$(echo "$line" | cut -f 2-)" || echo "$line"
	done
}

parse_rss() { # < data
	set -e
	items=$(xml sel -T -t -m //item -v pubDate -o "$TAB" -v title -o "$TAB" -v link -n 2>/dev/null)
	echo "$items" | format_feed_dates '%a, %d %b %Y %T'
}
parse_atom() { # < data
	set -e
	items=$(xml sel -T -N atom='http://www.w3.org/2005/Atom' -t -m //atom:entry -v atom:updated -o "$TAB" -v atom:title -o "$TAB" -v atom:link/@href -n 2>/dev/null)
	echo "$items" | format_feed_dates '%Y-%m-%dT%H:%M:%S'
}
parse_rdf() { # < data
	set -e
	items=$(xml sel -T -N purl='http://purl.org/rss/1.0/' -t -m //purl:item -v dc:date -o "$TAB" -v purl:title -o "$TAB" -v purl:link -n 2>/dev/null)
	echo "$items" | format_feed_dates '%Y-%m-%dT%H:%M:%S'
}
parse_feed() { # < data
	input=$(cat -)
	echo "$input" | parse_rss && return
	echo "$input" | parse_atom && return
	echo "$input" | parse_rdf && return
	return 1
}

update_read_urls() { # feedhash < urls
	set -e
	readfile="$DATA_DIR/$1.read"

	if [ -f "$readfile" ]; then
		merged_urls=$(cat - "$readfile" | sort -u)
		new_urls=$(echo "$merged_urls" | comm -13 "$readfile" -)
		[ -z "$new_urls" ] || {
			echo "$new_urls"
			echo "$merged_urls" > "$readfile"
		}
	else
		new_urls=$(sort -u)
		echo "$new_urls" | tee "$readfile"
	fi
}

fetch_unread() { # feedurl
	set -e
	feedurl=$1
	data=$(curl -fsL "$feedurl")
	feedhash=$(echo "$feedurl" | sha1sum | cut -d ' ' -f 1)
	items=$(echo "$data" | parse_feed)

	# A little dirty, could possibly be improved with awk
	unread_urls=$(echo "$items" | cut -f 3 | update_read_urls "$feedhash")
	[ -z "$unread_urls" ] || echo "$items" | grep "$unread_urls"
}

usage() {
	printf 'rsscli.sh
USAGE:
	add <name> <url>
	del <name>
	feeds
	run
	purge-read
'
	exit 1
}

case $1 in
	add)
		[ -z "$3" ] && usage
		printf '%s\t%s\n' "$2" "$3" >> "$FEEDS_FILE"
		sort -u "$FEEDS_FILE" -o "$FEEDS_FILE"
		;;
	del)
		[ -z "$2" ] && usage
		newfile=$(grep -v "$2$TAB" "$FEEDS_FILE")
		echo "$newfile" > "$FEEDS_FILE"
		;;
	feeds)
		cat "$FEEDS_FILE"
		;;
	run)
		# TODO: parallel
		while read -r line; do
			unread=$(fetch_unread "$(echo "$line" | cut -f 2-)")
			[ -n "$unread" ] && printf "%s\n%s\n\n" "$(echo "$line" | cut -f 1)" "$unread"
		done < "$FEEDS_FILE"
		exit 0
		;;
	purge-read)
		rm "$DATA_DIR"/*.read
		;;
	help|*)
		usage
		;;
esac
