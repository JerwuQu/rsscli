#!/bin/sh
while read -r title; do
	printf '<h1>%s</h1>\n' "$(echo "$title" | xml esc)"
	while read -r line; do
		[ -z "$line" ] && break
		printf '%s: <a href="%s">%s</a><br>\n' "$(echo "$line" | cut -f 1 | xml esc)" "$(echo "$line" | cut -f 3 | xml esc)" "$(echo "$line" | cut -f 2 | xml esc)"
	done
	printf '<br>\n'
done
