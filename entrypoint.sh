#!/bin/sh
config_file=/etc/nginx/conf.d/default.conf

S3_PATH=${S3_PATH:-https://$S3_BUCKET.s3-$S3_REGION.amazonaws.com}

touch $config_file 2>/dev/null
if [ $? = 0 ]; then
  echo Configuring nginx for bucket: $S3_BUCKET.
  cat > $config_file <<-EOF
  server {
    listen 443;
    server_name munki;

    location ~ '^/repo/(.*)\$' {
      limit_except GET {
        deny all;
      }

      set \$key \$1;

      # Setup AWS Authorization header
      set \$aws_signature '';

      # the only reason we need lua is to get the current date
      set_by_lua \$now "return ngx.cookie_time(ngx.time())";

      # the access key
      set \$aws_access_key '$AWS_ACCESS_KEY';
      set \$aws_secret_key '$AWS_SECRET_KEY';

      # the actual string to be signed
      # see: http://docs.amazonwebservices.com/AmazonS3/latest/dev/RESTAuthentication.html
      set \$string_to_sign "\$request_method\n\n\n\nx-amz-date:\$now\n/$S3_BUCKET/\$key";

      # create the hmac signature
      set_hmac_sha1 \$aws_signature \$aws_secret_key \$string_to_sign;
      # encode the signature with base64
      set_encode_base64 \$aws_signature \$aws_signature;
      proxy_set_header x-amz-date \$now;
      proxy_set_header Authorization "AWS \$aws_access_key:\$aws_signature";

      # rewrite .* /\$key break;

      # we need to set the host header here in order to find the bucket
      proxy_set_header Host $S3_BUCKET.s3.amazonaws.com;
      rewrite .* /\$key break;

      proxy_pass $S3_PATH;
    }
  }
EOF
else
  echo Could not write to $config_file. Manual configuration is expected. \
    >> /dev/stderr
fi

if [ -z "$1" ] || [ "${1:0:1}" = "-" ]; then
  set -- nginx $@
fi

exec dumb-init $@
