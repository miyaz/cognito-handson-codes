# サーバレスで簡易Dropbox
## JAWS-UG沖縄 Amazon Cognitoハンズオン 2017-10-21
---

資料は[こちら](https://www.slideshare.net/secret/rrYCjGV1wSgJec)

注）手順に出てくる`miyaz`の部分は自分の名前に置き換えてください

* マネコンからCognitoを開く

* ユーザプールを作成
  * `名前` でプール名に`userpool-miyaz`を指定し`デフォルトを確認する`をクリック 
  * 作成
  * 表示されるプールIDとプールARNを控える（あとで使う）

* アプリクライアントを作成
  * `アプリクライアント` を選択
  * アプリクライアント名に`myapp-miyaz`を指定
  * `クライアントシークレットを生成する`チェックを外し作成
  * 表示されるクライアントIDを控え（あとで使う）

* フェデレーテッドアイデンティティを作成
  * IDプール名に`idpool_miyaz`を指定
  * `認証されていない ID に対してアクセスを有効にする` のチェックをつける
  * 認証プロバイダー にCognitoを選択、ユーザプール ID、アプリクライアントIDには先に発行したものを入力
  * プールを作成ボタンをクリック、その後の許可ボタンもクリック
  * 表示されるIDプールIDを控える（あとで使う）
  * このリポジトリをダウンロード
    * `git clone git://github.com/miyaz/cognito-handson-codes.git`

* サインアップページ／アクティベーションページ作成
  * signup.html/activation.html修正
    * <IdentityPoolId>をIDプールIDに置き換える
    * <UserPoolId>をユーザプールIDに置き換えるÂ
    * <AppClientId>をアプリクライアントIDに置き換える
  * signup.htmlを開き、必要情報入力してサインアップ
    * メールに検証コードが届くのでactivation.htmlを開きユーザをアクティベート

* サインイン／マイページ作成
  * signup.html/activation.html修正
    * <IdentityPoolId>をIDプールIDに置き換える
    * <UserPoolId>をユーザプールIDに置き換える
    * <AppClientId>をアプリクライアントIDに置き換える
  * signin.htmlを開き、必要情報入力してサインインし、マイページが表示されることを確認

* マイフォルダページ作成
  * `cognito-myfolder-miyaz`バケット作成
    * CORS設定
```
<CORSConfiguration>
  <CORSRule>
    <AllowedOrigin>*</AllowedOrigin>
    <AllowedMethod>GET</AllowedMethod>
    <AllowedMethod>PUT</AllowedMethod>
    <AllowedMethod>DELETE</AllowedMethod>
    <MaxAgeSeconds>3000</MaxAgeSeconds>
    <AllowedHeader>*</AllowedHeader>
  </CORSRule>
</CORSConfiguration>
```
  * 認証されたロール{Cognito_idpool_miyazAuth_Role}にS3アクセス権付与
    * <BucketName>を作成したバケット名に置き換える
```
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
                "arn:aws:s3:::<BucketName>"
            ],
            "Condition": {
                "StringLike": {
                    "s3:prefix": [
                        "${cognito-identity.amazonaws.com:sub}/*"
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
                "arn:aws:s3:::<BucketName>/${cognito-identity.amazonaws.com:sub}/*"
            ]
        }
    ]
}
```
  * myfolder.html修正
    * <IdentityPoolId>をIDプールIDに置き換える
    * <UserPoolId>をユーザプールIDに置き換える
    * <AppClientId>をアプリクライアントIDに置き換える
    * <BucketName>をバケット名に置き換える
    * myfolder.htmlを開き、アップロード／ダウンロードができることを確認

# 完成
