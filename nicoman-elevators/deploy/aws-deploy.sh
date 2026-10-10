#!/usr/bin/env bash
# Provisions and deploys the Nicoman Elevators site on AWS:
#   S3 (private, versioned) -> CloudFront (OAC, HTTPS) -> nico.atla.in
# Safe to re-run: each step checks for an existing resource first.
#
# Requires AWS credentials in the environment (AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY)
# and optionally AWS_REGION (default ap-south-1, Mumbai).
set -euo pipefail

DOMAIN="${DOMAIN:-nico.atla.in}"
ZONE_NAME="${ZONE_NAME:-atla.in}"          # Route 53 hosted zone that holds the domain (leave empty to skip DNS)
REGION="${AWS_REGION:-ap-south-1}"
SITE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
BUCKET="${BUCKET:-nicoman-elevators-site-${ACCOUNT}}"
OAC_NAME="nicoman-elevators-oac"
CACHE_OPTIMIZED="658327ea-f89d-4fab-a63d-7e88639e58f6"   # AWS managed: CachingOptimized
SECURITY_HEADERS="67f7725c-6f97-4210-82d7-5512b31e9d03"   # AWS managed: SecurityHeadersPolicy

echo "Account: ${ACCOUNT}  Region: ${REGION}  Bucket: ${BUCKET}  Domain: ${DOMAIN}"

# 1. Bucket: private, block public access, versioning for backups
if ! aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
fi
aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
echo "[ok] bucket ready"

# 2. Certificate (CloudFront needs it in us-east-1)
CERT_ARN="$(aws acm list-certificates --region us-east-1 \
  --query "CertificateSummaryList[?DomainName=='${DOMAIN}'].CertificateArn | [0]" --output text)"
if [ "$CERT_ARN" = "None" ] || [ -z "$CERT_ARN" ]; then
  CERT_ARN="$(aws acm request-certificate --region us-east-1 --domain-name "$DOMAIN" \
    --validation-method DNS --query CertificateArn --output text)"
  sleep 5
fi
STATUS="$(aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" \
  --query Certificate.Status --output text)"
if [ "$STATUS" != "ISSUED" ]; then
  VAL_NAME="$(aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" \
    --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Name' --output text)"
  VAL_VALUE="$(aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" \
    --query 'Certificate.DomainValidationOptions[0].ResourceRecord.Value' --output text)"
  echo "[action] Certificate pending DNS validation. Add this CNAME:"
  echo "         ${VAL_NAME}  CNAME  ${VAL_VALUE}"
  if [ -n "$ZONE_NAME" ]; then
    ZONE_ID="$(aws route53 list-hosted-zones-by-name --dns-name "$ZONE_NAME" \
      --query "HostedZones[?Name=='${ZONE_NAME}.'].Id | [0]" --output text | sed 's#/hostedzone/##')"
    if [ -n "$ZONE_ID" ] && [ "$ZONE_ID" != "None" ]; then
      aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch "{
        \"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"${VAL_NAME}\",\"Type\":\"CNAME\",
        \"TTL\":300,\"ResourceRecords\":[{\"Value\":\"${VAL_VALUE}\"}]}}]}" >/dev/null
      echo "[ok] validation CNAME written to Route 53; waiting for ISSUED"
      aws acm wait certificate-validated --region us-east-1 --certificate-arn "$CERT_ARN"
    fi
  fi
  if [ "$(aws acm describe-certificate --region us-east-1 --certificate-arn "$CERT_ARN" \
        --query Certificate.Status --output text)" != "ISSUED" ]; then
    echo "[stop] certificate not issued yet. Add the CNAME above, then re-run this script."
    exit 1
  fi
fi
echo "[ok] certificate issued"

# 3. Origin Access Control
OAC_ID="$(aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[?Name=='${OAC_NAME}'].Id | [0]" --output text)"
if [ "$OAC_ID" = "None" ] || [ -z "$OAC_ID" ]; then
  OAC_ID="$(aws cloudfront create-origin-access-control --origin-access-control-config "{
    \"Name\":\"${OAC_NAME}\",\"Description\":\"Nicoman site bucket\",
    \"SigningProtocol\":\"sigv4\",\"SigningBehavior\":\"always\",\"OriginAccessControlOriginType\":\"s3\"}" \
    --query OriginAccessControl.Id --output text)"
fi

# 4. CloudFront distribution
DIST_ID="$(aws cloudfront list-distributions --query \
  "DistributionList.Items[?contains(Aliases.Items, '${DOMAIN}')].Id | [0]" --output text)"
if [ "$DIST_ID" = "None" ] || [ -z "$DIST_ID" ]; then
  ORIGIN="${BUCKET}.s3.${REGION}.amazonaws.com"
  DIST_ID="$(aws cloudfront create-distribution-with-tags --distribution-config-with-tags "{
    \"DistributionConfig\":{
      \"CallerReference\":\"nicoman-$(date +%s)\",
      \"Comment\":\"Nicoman Elevators site\",
      \"Enabled\":true,
      \"DefaultRootObject\":\"index.html\",
      \"Aliases\":{\"Quantity\":1,\"Items\":[\"${DOMAIN}\"]},
      \"Origins\":{\"Quantity\":1,\"Items\":[{
        \"Id\":\"s3-site\",\"DomainName\":\"${ORIGIN}\",\"OriginAccessControlId\":\"${OAC_ID}\",
        \"S3OriginConfig\":{\"OriginAccessIdentity\":\"\"}}]},
      \"DefaultCacheBehavior\":{
        \"TargetOriginId\":\"s3-site\",\"ViewerProtocolPolicy\":\"redirect-to-https\",
        \"Compress\":true,\"AllowedMethods\":{\"Quantity\":2,\"Items\":[\"GET\",\"HEAD\"]},
        \"CachePolicyId\":\"${CACHE_OPTIMIZED}\",\"ResponseHeadersPolicyId\":\"${SECURITY_HEADERS}\"},
      \"CustomErrorResponses\":{\"Quantity\":1,\"Items\":[{
        \"ErrorCode\":403,\"ResponsePagePath\":\"/index.html\",\"ResponseCode\":\"404\",\"ErrorCachingMinTTL\":60}]},
      \"PriceClass\":\"PriceClass_200\",
      \"ViewerCertificate\":{\"ACMCertificateArn\":\"${CERT_ARN}\",\"SSLSupportMethod\":\"sni-only\",
        \"MinimumProtocolVersion\":\"TLSv1.2_2021\"},
      \"HttpVersion\":\"http2and3\"},
    \"Tags\":{\"Items\":[{\"Key\":\"Project\",\"Value\":\"nicoman-elevators\"}]}}" \
    --query Distribution.Id --output text)"
  echo "[ok] CloudFront distribution created: ${DIST_ID}"
fi
DIST_DOMAIN="$(aws cloudfront get-distribution --id "$DIST_ID" --query Distribution.DomainName --output text)"
DIST_ARN="arn:aws:cloudfront::${ACCOUNT}:distribution/${DIST_ID}"

# 5. Bucket policy: only this distribution may read
aws s3api put-bucket-policy --bucket "$BUCKET" --policy "{
  \"Version\":\"2012-10-17\",\"Statement\":[{
    \"Sid\":\"AllowCloudFrontRead\",\"Effect\":\"Allow\",
    \"Principal\":{\"Service\":\"cloudfront.amazonaws.com\"},
    \"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::${BUCKET}/*\",
    \"Condition\":{\"StringEquals\":{\"AWS:SourceArn\":\"${DIST_ARN}\"}}}]}"
echo "[ok] bucket policy applied"

# 6. DNS: point nico.atla.in at CloudFront (Route 53 if the zone is there)
if [ -n "$ZONE_NAME" ]; then
  ZONE_ID="$(aws route53 list-hosted-zones-by-name --dns-name "$ZONE_NAME" \
    --query "HostedZones[?Name=='${ZONE_NAME}.'].Id | [0]" --output text | sed 's#/hostedzone/##')"
  if [ -n "$ZONE_ID" ] && [ "$ZONE_ID" != "None" ]; then
    aws route53 change-resource-record-sets --hosted-zone-id "$ZONE_ID" --change-batch "{
      \"Changes\":[{\"Action\":\"UPSERT\",\"ResourceRecordSet\":{\"Name\":\"${DOMAIN}.\",\"Type\":\"A\",
      \"AliasTarget\":{\"HostedZoneId\":\"Z2FDTNDATAQYW2\",\"DNSName\":\"${DIST_DOMAIN}\",\"EvaluateTargetHealth\":false}}}]}" >/dev/null
    echo "[ok] Route 53 alias ${DOMAIN} -> ${DIST_DOMAIN}"
  else
    echo "[action] No Route 53 zone for ${ZONE_NAME}. Add CNAME: ${DOMAIN} -> ${DIST_DOMAIN}"
  fi
fi

# 7. Upload site. HTML is short-cached so edits show quickly; assets cached for a week.
cd "$SITE_DIR"
aws s3 sync . "s3://${BUCKET}" --delete --exclude ".git/*" --exclude "backend/*" \
  --exclude "README.md" --exclude "deploy/*" --exclude ".gitignore" \
  --cache-control "public,max-age=604800" --exclude "*.html"
aws s3 sync . "s3://${BUCKET}" --exclude ".git/*" --exclude "backend/*" \
  --exclude "README.md" --exclude "deploy/*" --exclude ".gitignore" \
  --include "*.html" --cache-control "public,max-age=300" --content-type "text/html; charset=utf-8"
echo "[ok] site uploaded"

aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" >/dev/null
echo "[ok] cache invalidated"
echo "Done. Site: https://${DOMAIN}  (CloudFront: https://${DIST_DOMAIN})"
