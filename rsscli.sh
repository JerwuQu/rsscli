#!/bin/sh
set -e
DATA_DIR=${RSSCLI_DIR:="$HOME/.rsscli"}
FEEDS_FILE="$DATA_DIR/feeds"
TAB='	'

mkdir -p "$DATA_DIR"

parse_rss() { # < data
	set -e
	xml sel -T -t -m //item -v pubDate -o "$TAB" -v title -o "$TAB" -v link -n 2>/dev/null
}
parse_atom() { # < data
	set -e
	xml sel -T -N atom='http://www.w3.org/2005/Atom' -t -m //atom:entry -v atom:updated -o "$TAB" -v atom:title -o "$TAB" -v atom:link/@href -n 2>/dev/null
}
parse_rdf() { # < data
	set -e
	xml sel -T -N purl='http://purl.org/rss/1.0/' -t -m //purl:item -v dc:date -o "$TAB" -v purl:title -o "$TAB" -v purl:link -n 2>/dev/null
}
parse_feed() { # < data
	input=$(cat -)
	echo "$input" | parse_rss && return
	echo "$input" | parse_atom && return
	echo "$input" | parse_rdf && return
	return 1
}

update_read_urls() { # urlhash < urls
	readfile="$DATA_DIR/$1.read"
	if [ -f "$readfile" ]; then
		new_urls=$(cat - "$readfile" | sort -u | comm -13 "$readfile" -)
		[ -z "$new_urls" ] || {
			echo "$new_urls" | tee -a "$readfile"
			sort -u "$readfile" -o "$readfile"
		}
	else
		sort -u | tee "$readfile"
	fi
}

fetch_unread() { # urlhash < data
	# A little dirty, could possibly be improved with awk
	items=$(parse_feed)
	unread_urls=$(echo "$items" | cut -f 3 | update_read_urls "$1")
	[ -z "$unread_urls" ] || echo "$items" | grep "$unread_urls"
}

usage() {
	printf 'rsscli.sh
USAGE:
	add <name> <url>  -  add a new feed
	del <name>        -  remove a feed
	run               -  fetch all feeds and output updates
	feeds             -  print all feed titles and urls to output
	format-feeds      -  format feeds file, required after doing manual edits
	purge-history     -  purge feed read history
'
	exit 1
}

case $1 in
	add)
		[ -z "$3" ] && usage
		printf '%s\t%s\n' "$2" "$3"  >> "$FEEDS_FILE"
		"$0" format-feeds
		;;
	del)
		[ -z "$2" ] && usage
		newfile=$(grep -v "$2$TAB" "$FEEDS_FILE")
		echo "$newfile" > "$FEEDS_FILE"
		;;
	run)
		while read -r line; do
			printf 'url="%s"\noutput="/tmp/rsscli-feed-%s"\n\n' "$(echo "$line" | cut -f 2)" "$(echo "$line" | cut -f 3)"
		done < "$FEEDS_FILE" | curl -LZK -
		while read -r line; do
			echo "$line" | cut -f 1 1>&2
			urlhash=$(echo "$line" | cut -f 3)
			unread=$(fetch_unread "$urlhash" < "/tmp/rsscli-feed-$urlhash") || continue
			[ -z "$unread" ] || printf "%s\n%s\n\n" "$(echo "$line" | cut -f 1)" "$unread"
		done < "$FEEDS_FILE"
		;;
	feeds)
		cut -f 1-2 < "$FEEDS_FILE"
		;;
	format-feeds)
		feeds=$(while read -r line; do
			title=$(echo "$line" | cut -f 1)
			url=$(echo "$line" | cut -f 2)
			urlhash=$(echo "$url" | sha1sum | cut -d ' ' -f 1)
			printf '%s\t%s\t%s\n' "$title" "$url" "$urlhash"
		done < "$FEEDS_FILE")
		echo "$feeds" | sort -ufo "$FEEDS_FILE"
		;;
	purge-history)
		rm "$DATA_DIR"/*.read
		;;
	help|*)
		usage
		;;
esac
