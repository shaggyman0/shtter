#!/bin/sh
 
CKEY=""
CSECRET=""
AKEY=""
ASECRET=""
 
HTTP_GET="wget -q -O -"
HTTP_POST="wget -q -O - --post-data"
#HTTP_GET="curl -s"
#HTTP_POST="curl -s --data"
 
TMPDIR="/tmp"
 
PREFIX=""
SUFFIX=" #shtter"
 
GenerateNonce()
{
dd if=/dev/urandom bs=1024 count=1 2>/dev/null | md5sum | cut -c1-32
}
 
GetTimeStamp()
{
date +%s
}
 
Encode()
{
echo "$@" | sed 's/./\0\n/g' | grep '[^-._~0-9a-zA-Z]' | sort | uniq | while read l
do
 if [ "$l" == "" ]; then l=" "; fi
  
 HEX="`echo -n \"$l\" | hexdump -e '16/1 "%02X" "\n"'`"
  
 if [ "$l" == "/" ]; then l="\/"; fi
 echo "s/$l/$HEX"
done | sed 's/ *$//; s/\([0-9A-Z]\{2\}\)/%\1/g; s/$/\/g/' >"$TMPDIR/rep.sed"
 
echo "$@" | sed -f "$TMPDIR/rep.sed"
 
rm "$TMPDIR/rep.sed"
}
 
Decode()
{
HEX="`echo -e "$@" | sed 's/&#[0-9]\+;/\n\0\n/g' | sed '/^&#[0-9]\+;$/!d; s/[&#;]//g' | sort | uniq`"
HEX="`echo -e \"$HEX\" | while read l; do echo -n \"$l\" | hexdump -e '8/1 "%02x00"'; printf '%04x\n' "$l"; done`"
HEX="`echo -e \"$HEX\" | sed 's/  00//g; s/^/73002f0026002300/; s/\(..\)\(..\)$/3b002f00\2\12f0067000a00/'`"
HEX="`echo $HEX | sed 's/ //g; s/../\\\x\0/g'`"
printf "$HEX" | iconv -f UTF-16 -t UTF-8 >"$TMPDIR/rep.sed"
 
echo -e "$@" | sed -f "$TMPDIR/rep.sed"
 
rm "$TMPDIR/rep.sed"
}
 
GenerateHash()
{
EURL="`Encode $2`"
EPARAM="`Encode $3`"
QUERY="$1&$EURL&$EPARAM"
 
HASH="`echo -n \"$QUERY\" | openssl sha1 -hmac \"$CSECRET&$ASECRET\" -binary | openssl base64`"
Encode "$HASH"
}
 
GetRequestToken()
{
URL="https://api.twitter.com/oauth/request_token"
NONCE="`GenerateNonce`"
TIMESTAMP="`GetTimeStamp`"
PARAM="oauth_callback=oob&oauth_consumer_key=$CKEY&oauth_nonce=$NONCE&oauth_signature_method=HMAC-SHA1&oauth_timestamp=$TIMESTAMP&oauth_version=1.0"
HASH="`GenerateHash \"POST\" \"$URL\" \"$PARAM\"`"
RTOKEN="`wget -q -O - --post-data=\"\" --header=\"Authorization: OAuth oauth_nonce=\"$NONCE\", oauth_callback=\"oob\", oauth_signature_method=\"HMAC-SHA1\", oauth_timestamp=\"$TIMESTAMP\", oauth_consumer_key=\"$CKEY\", oauth_signature=\"$HASH\", oauth_version=\"1.0\"\" $URL`"
if [ "$RTOKEN" == "" ]; then
 echo "can not get request token" >&2
 exit 1
fi
 
RKEY="`echo \"$RTOKEN\" | sed 's/.*oauth_token=\([^&]*\).*/\1/'`"
RSECRET="`echo \"$RTOKEN\" | sed 's/.*oauth_token_secret=\([^&]*\).*/\1/'`"
 
echo "open this url in your browsser and input pin" >&2
echo "https://twitter.com/oauth/authorize?oauth_token=$RKEY" >&2
echo -n "pin > " >&2
read PIN
 
echo "$RKEY $RSECRET $PIN"
}
 
GetAccessToken()
{
RKEY="$1"
RSECRET="$2"
PIN="$3"
 
URL="https://twitter.com/oauth/access_token"
PARAM="oauth_consumer_key=$CKEY&oauth_nonce=`GenerateNonce`&oauth_signature_method=HMAC-SHA1&oauth_timestamp=`GetTimeStamp`&oauth_token=$RKEY&oauth_verifier=$PIN&oauth_version=1.0"
HASH="`GenerateHash \"GET\" \"$URL\" \"$PARAM\"`"
 
ATOKEN="`$HTTP_GET \"$URL?$PARAM&oauth_signature=$HASH\"`"
if [ "$ATOKEN" == "" ]; then
 echo "can not get access token" >&2
 exit 1
fi
 
AKEY="`echo $ATOKEN | sed 's/.*oauth_token=\([^&]*\).*/\1/'`"
ASECRET="`echo $ATOKEN | sed 's/.*oauth_token_secret=\([^&]*\).*/\1/'`"
 
sed -i "1,/^AKEY/ s/^\(AKEY=\).*/\1\"$AKEY\"/" "$0"
sed -i "1,/^ASECRET/ s/^\(ASECRET=\).*/\1\"$ASECRET\"/" "$0"
}
 
GetUsersMe()
{
URL="https://api.twitter.com/2/users/me"
NONCE="`GenerateNonce`"
TIMESTAMP="`GetTimeStamp`"
PARAM="oauth_consumer_key=$CKEY&oauth_nonce=$NONCE&oauth_signature_method=HMAC-SHA1&oauth_timestamp=$TIMESTAMP&oauth_token=$AKEY&oauth_version=1.0"
HASH="`GenerateHash \"GET\" \"$URL\" \"$PARAM\"`"
 
JSON="`wget -q -O - --header=\"Content-Type: application/json" --header=\"Authorization: OAuth oauth_nonce=\"$NONCE\", oauth_signature_method=\"HMAC-SHA1\", oauth_timestamp=\"$TIMESTAMP\", oauth_consumer_key=\"$CKEY\", oauth_token=\"$AKEY\", oauth_signature=\"$HASH\", oauth_version=\"1.0\"\" $URL`"
if [ "$JSON" == "" ]
then
 echo "can not get TimeLine" >&2
 exit 1
fi
 
echo $JSON
}
 
UpdateTimeLine()
{
TWEET="$PREFIX$@$SUFFIX"
if [ "$TWEET" == "" ]
then
 echo "can not tweet" >&2
 exit 1
fi
 
URL="https://api.twitter.com/2/tweets"
NONCE="`GenerateNonce`"
TIMESTAMP="`GetTimeStamp`"
PARAM="oauth_consumer_key=$CKEY&oauth_nonce=$NONCE&oauth_signature_method=HMAC-SHA1&oauth_timestamp=$TIMESTAMP&oauth_token=$AKEY&oauth_version=1.0"
HASH="`GenerateHash \"POST\" \"$URL\" \"$PARAM\"`"
 
JSON="`wget -q -O - --post-data=\"{ \\\"text\\\": \\\"$TWEET\\\" }\" --header=\"Content-Type: application/json" --header=\"Authorization: OAuth oauth_nonce=\"$NONCE\", oauth_signature_method=\"HMAC-SHA1\", oauth_timestamp=\"$TIMESTAMP\", oauth_consumer_key=\"$CKEY\", oauth_token=\"$AKEY\", oauth_signature=\"$HASH\", oauth_version=\"1.0\"\" $URL`"
if [ "$JSON" == "" ]
then
 echo "can not post tweet" >&2
 exit 1
fi
}
 
if [ "$AKEY" == "" -o "$ASECRET" == "" ]
then
 RTOKEN="`GetRequestToken`"
 GetAccessToken $RTOKEN
else
 ARG="$1"
 shift 1
  
 case "$ARG" in
  init)
   sed -i "1,/^AKEY/ s/^\(AKEY=\).*/\1/" "$0"
   sed -i "1,/^ASECRET/ s/^\(ASECRET=\).*/\1/" "$0"
   ;;
  update)
   UpdateTimeLine "$@"
   ;;
  *)
   GetUsersMe
   ;;
 esac
fi
