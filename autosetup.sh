#!/bin/bash

#===========================================================#
# ハンズオンの手順をAPIを使って全て自動で行うスクリプトです #
# 前提）                                                    #
# ・PowerUser相当の権限でaws cliを実行できる環境があること  #
#===========================================================#

###########
# 環境設定

# 実行するユーザ名 ・・・ この名前を基ににいろいろなリソース名を決定します
HANDSON_USER=hogehoge

# リージョン指定 ・・・ 東京リージョンでしか確認していませんw。たぶん他リージョンでもOK
REGION=ap-northeast-1

# AWSアカウントID ・・・ 利用するAWSアカウントのID(数字12桁のやつ)を指定してください
AWS_ACCOUNT_ID=999999999999

###########
# 処理開始

export AWS_DEFAULT_REGION=${REGION}

echo "ユーザプール作成"
USERPOOL_NAME=userpool-${HANDSON_USER}
USERPOOL_ID=$(aws cognito-idp create-user-pool \
                  --pool-name ${USERPOOL_NAME} \
                  --auto-verified-attributes email |\
                  jq -r .UserPool.Id)
[ -z ${USERPOOL_ID} ] && exit 1
echo " -> ${USERPOOL_ID}"

echo "アプリクライアント作成"
CLIENT_NAME=myapp-${HANDSON_USER}
CLIENT_ID=$(aws cognito-idp create-user-pool-client \
                --user-pool-id ${USERPOOL_ID} --client-name ${CLIENT_NAME} |\
                jq -r .UserPoolClient.ClientId)
[ -z ${CLIENT_ID} ] && exit 1
echo " -> ${CLIENT_ID}"

echo "IDプール作成"
IDPOOL_NAME=idpool_${HANDSON_USER}
IDPOOL_ID=$(aws cognito-identity create-identity-pool \
                --identity-pool-name ${IDPOOL_NAME} \
                --allow-unauthenticated-identities \
                --cognito-identity-providers ProviderName=cognito-idp.${REGION}.amazonaws.com/${USERPOOL_ID},ClientId=${CLIENT_ID},ServerSideTokenCheck=false |\
                jq -r .IdentityPoolId)
[ -z ${IDPOOL_ID} ] && exit 1
echo " -> ${IDPOOL_ID}"

# ロール/ポリシー定義
IDPOOL_AUTH_ROLENAME=Cognito_${IDPOOL_NAME}Auth_Role
IDPOOL_UNAUTH_ROLENAME=Cognito_${IDPOOL_NAME}Unauth_Role
IDPOOL_AUTH_ROLEARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IDPOOL_AUTH_ROLENAME}
IDPOOL_UNAUTH_ROLEARN=arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IDPOOL_UNAUTH_ROLENAME}
IDPOOL_AUTH_POLICYNAME=usingCLI_${IDPOOL_AUTH_ROLENAME}_$(date '+%s%3N')
IDPOOL_UNAUTH_POLICYNAME=usingCLI_${IDPOOL_UNAUTH_ROLENAME}_$(date '+%s%3N')
# 未認証ロール用ポリシードキュメント
IDPOOL_UNAUTH_POLICYDOC=$(cat << EOS
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "mobileanalytics:PutEvents",
        "cognito-sync:*",
        "cognito-identity:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOS
)
# 認証ロール用ポリシードキュメント
S3_BUCKET_NAME=easydropbox-${HANDSON_USER}
IDPOOL_AUTH_POLICYDOC=$(cat << EOS
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "mobileanalytics:PutEvents",
                "cognito-sync:*",
                "cognito-identity:*"
            ],
            "Resource": [
                "*"
            ]
        },
        {
            "Action": [
                "s3:ListBucket"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}"
            ],
            "Condition": {
                "StringLike": {
                    "s3:prefix": [
                        "\${cognito-identity.amazonaws.com:sub}/*"
                    ]
                }
            }
        },
        {
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}/\${cognito-identity.amazonaws.com:sub}/*"
            ]
        }
    ]
}
EOS
)
# 未認証ロール用AssumeRoleポリシードキュメント
IDPOOL_UNAUTH_ASSUMEROLE_POLICYDOC=$(cat << EOS
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "${IDPOOL_ID}"
        },
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "unauthenticated"
        }
      }
    }
  ]
}
EOS
)
# 認証ロール用AssumeRoleポリシードキュメント
IDPOOL_AUTH_ASSUMEROLE_POLICYDOC=$(cat << EOS
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "cognito-identity.amazonaws.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "cognito-identity.amazonaws.com:aud": "${IDPOOL_ID}"
        },
        "ForAnyValue:StringLike": {
          "cognito-identity.amazonaws.com:amr": "authenticated"
        }
      }
    }
  ]
}
EOS
)

echo "Federated Identity 認証済みロール作成"
aws iam create-role --role-name ${IDPOOL_AUTH_ROLENAME} \
                    --assume-role-policy-document "${IDPOOL_AUTH_ASSUMEROLE_POLICYDOC}" >/dev/null
[ $? -ne 0 ] && exit 1
echo " -> ${IDPOOL_AUTH_ROLENAME}"

echo "Federated Identity 未認証時ロール作成"
aws iam create-role --role-name ${IDPOOL_UNAUTH_ROLENAME} \
                    --assume-role-policy-document "${IDPOOL_UNAUTH_ASSUMEROLE_POLICYDOC}" >/dev/null
[ $? -ne 0 ] && exit 1
echo " -> ${IDPOOL_UNAUTH_ROLENAME}"

echo "認証済みロール用インラインポリシー作成"
aws iam put-role-policy --role-name ${IDPOOL_AUTH_ROLENAME} \
                        --policy-name ${IDPOOL_AUTH_POLICYNAME} \
                        --policy-document "${IDPOOL_AUTH_POLICYDOC}"
[ $? -ne 0 ] && exit 1
echo " -> ${IDPOOL_AUTH_POLICYNAME}"

echo "未認証時ロール用インラインポリシー作成"
aws iam put-role-policy --role-name ${IDPOOL_UNAUTH_ROLENAME} \
                        --policy-name ${IDPOOL_UNAUTH_POLICYNAME} \
                        --policy-document "${IDPOOL_UNAUTH_POLICYDOC}"
[ $? -ne 0 ] && exit 1
echo " -> ${IDPOOL_UNAUTH_POLICYNAME}"

echo "認証済み/未認証ロールをIDプールに紐付け"
aws cognito-identity set-identity-pool-roles \
                     --identity-pool-id ${IDPOOL_ID} \
                     --roles unauthenticated=${IDPOOL_UNAUTH_ROLEARN},authenticated=${IDPOOL_AUTH_ROLEARN}
[ $? -ne 0 ] && exit 1
echo " -> 紐付けOK"

echo "ハンズオンコード取得"
TMPDIR=`mktemp -dp /dev/shm`
git clone git://github.com/miyaz/cognito-handson-codes.git ${TMPDIR}
[ $? -ne 0 ] && exit 1
echo " -> dirpath: ${TMPDIR}"

echo "コード書き換え"
sed -i "s/<IdentityPoolId>/${IDPOOL_ID}/g" ${TMPDIR}/*html
sed -i "s/<UserPoolId>/${USERPOOL_ID}/g" ${TMPDIR}/*html
sed -i "s/<AppClientId>/${CLIENT_ID}/g" ${TMPDIR}/*html
sed -i "s/<BucketName>/${S3_BUCKET_NAME}/g" ${TMPDIR}/*html
rm -rf ${TMPDIR}/.git
echo " -> done."

# S3バケットのCORS定義
S3_BUCKET_CORS=$(cat << EOS
{
    "CORSRules": [
        {
            "AllowedOrigins": ["*"],
            "AllowedHeaders": ["*"],
            "AllowedMethods": ["GET", "PUT", "DELETE"],
            "MaxAgeSeconds": 3000
        }
    ]
}
EOS
)

echo "S3バケット作成"
aws s3 mb s3://${S3_BUCKET_NAME}
[ $? -ne 0 ] && exit 1
echo " -> s3://${S3_BUCKET_NAME}"

echo "S3バケットCORS設定"
aws s3api put-bucket-cors --bucket ${S3_BUCKET_NAME} --cors-configuration "${S3_BUCKET_CORS}"
[ $? -ne 0 ] && exit 1
echo " -> done."

echo "コードアップロード"
aws s3 sync --acl public-read ${TMPDIR}/ s3://${S3_BUCKET_NAME}/
[ $? -ne 0 ] && exit 1
echo " -> done."

echo "全ての設定が完了しました"
echo "access to https://s3-${REGION}.amazonaws.com/${S3_BUCKET_NAME}/signup.html"

