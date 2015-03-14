#!/bin/sh

set -e

# Address of the internet voting server.
SERVER="https://localhost"

# Read the phone number from the first positional argument.
if [ -z "$1" ]; then
	echo "Usage: $0 <phone>" >&2
	exit 64
fi

# Phone number regex specified in Section 4.3 of the protocol description.
# Note: although the description specifies a minimum phone number length of 10,
# we use 7 here so that we can use the testnumber +37200007. The server stills
# accepts this.
if ! echo "$1" | grep -E '^\+[[:digit:]]{7,15}$' > /dev/null; then
	echo "$0: $1: must start with a leading '+' followed by 10 to 15 digits"
	exit 65
fi

phone="$1"

# Send the post request described in Section 4.3 to the server.
response=$(curl -sSF "phone=$phone" $SERVER/mobid.cgi)

# Parse response as specified in Section 4.1 of the protocol description.
version=$(echo "$response" | sed -n 1p)
status=$(echo "$response" | sed -n 2p)
body=$(echo "$response" | sed -n 3~1p)

if [ $version -ne 1 ]; then
	echo "$0: $version: unknown protocol version"
	exit 76
fi

if [ $status -ne 0 ]; then
	echo "$0: $status: non-zero status code: $body"
	exit 76
fi

# Parse response body as specified in Section 4.4 of the protocol description.
session=$(echo "$body" | cut -f 1)
code=$(echo "$body" | cut -f 2)

echo "Waiting for Mobile-ID authentication, control code: $code"

while true; do
	sleep 10

	# Poll the server with the request described in Section 4.6.
	# Note: The latest version of the protocol uses the value "auth"
	# instead of "true" for "poll".
	response=$(curl -sSF "session=$session" -F "poll=auth" $SERVER/mobid.cgi)

	# Parse response as specified in Section 4.1 of the protocol description.
	version=$(echo "$response" | sed -n 1p)
	status=$(echo "$response" | sed -n 2p)
	body=$(echo "$response" | sed -n 3~1p)

	if [ $version -ne 1 ]; then
		echo "$0: $version: unknown protocol version"
		exit 76
	fi

	case $status in
		0)
			# Authentication successful.
			break
			;;
		4)
			# Authentication still pending.
			continue
			;;
		*)
			echo "$0: $status: non-successful status code: $body"
			exit 76
			;;
	esac
done

echo "$body"
