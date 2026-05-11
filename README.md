# ruby-pure-mysql

Ruby による MySQL プロトコルおよびストレージエンジンの純粋な再実装プロジェクト。

## プロジェクトの目的
- MySQL の理解と実装。
- 外部の C 拡張に頼らない、Ruby のみによる MySQL 互換サーバーの構築。
- RSpec を用いた本物の MySQL との互換性テストの実施。

## 技術スタック
- **Language:** Ruby
- **Test:** RSpec (Comparison with real MySQL 8.0)
- **CI:** GitHub Actions
- **Environment:** Docker Compose (for real MySQL)

## 開発ロードマップ
- [ ] Initial Handshake パケットの送信
- [ ] 認証フロー（Password-less）のパス
- [ ] `SELECT 1;` への応答
- [ ] 基本的なデータ型のサポート
- [ ] 単純な INSERT / SELECT 命令の処理

## 実行方法
```bash
# 本物の MySQL を起動
docker compose up -d

# テストの実行
bundle exec rspec
```
