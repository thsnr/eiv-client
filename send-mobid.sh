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
	echo "$0: $1: must start with a leading '+' followed by 10 to 15 digits" >&2
	exit 65
fi

phone="$1"

# post_async sends an asynchronous request and then polls the server for the
# response.
post_async() {
	poll="$1"
	options="$2"
	session="$3"

	# Send request to the server.
	response=$(curl -sS $options $SERVER/mobid.cgi)

	# Parse response as specified in Section 4.1 of the protocol description.
	version=$(echo "$response" | sed -n 1p)
	status=$(echo "$response" | sed -n 2p)
	body=$(echo "$response" | sed -n 3~1p)

	if [ $version -ne 1 ]; then
		echo "$0: $version: unknown protocol version" >&2
		exit 76
	fi

	if [ $status -ne 0 ]; then
		echo "$0: $status: non-zero status code: $body" >&2
		exit 76
	fi

	# Parse response body as specified in either Section 4.4 or 4.5 of the
	# protocol description, depending on the polling type.
	case $poll in
		"auth")
			session=$(echo "$body" | cut -f 1)
			code=$(echo "$body" | cut -f 2)
			;;
		"vote")
			code="$body"
	esac

	echo "Waiting for Mobile-ID confirmation, control code: $code"

	while true; do
		sleep 10

		# Poll the server with the request described in Section 4.6.
		# Note: The latest version of the protocol uses the values
		# "auth" or "vote" instead of "true" for "poll". See
		# https://github.com/vvk-ehk/evalimine/blob/master/ivote-server/hes/middisp.py#L561
		response=$(curl -sSF "session=$session" -F "poll=$poll" $SERVER/mobid.cgi)

		# Parse response as specified in Section 4.1 of the protocol
		# description.
		version=$(echo "$response" | sed -n 1p)
		status=$(echo "$response" | sed -n 2p)
		body=$(echo "$response" | sed -n 3~1p)

		if [ $version -ne 1 ]; then
			echo "$0: $version: unknown protocol version" >&2
			exit 76
		fi

		case $status in
			0)
				# Confirmation successful.
				break
				;;
			4)
				# Confirmation still pending.
				continue
				;;
			*)
				echo "$0: $status: non-successful status code: $body" >&2
				exit 76
				;;
		esac
	done
}

# Send the post request described in Section 4.3 to the server.
echo -n "Authenticating..."
post_async "auth" "-F phone=$phone"

# Extract the session id from the response according to Section 4.8 of the
# protocol description.
for line in "$body"; do
	# Skip leading lines containing a colon.
	if echo "$line" | grep ':' > /dev/null; then
		continue
	fi
	session="$line"
	break
done

# Send the post request described in Section 4.10 to the server.
echo -n "Signing..."
post_async "vote" "-F session=$session -F vote=<-" "$session"

echo "Vote identifier: $body
