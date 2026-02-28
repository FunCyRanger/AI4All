//! Token wallet – tracks earned/spent tokens locally.
//! Receipts are signed with the node's Ed25519 key.

use anyhow::{Context, Result};
use chrono::Utc;
use ed25519_dalek::{SigningKey, VerifyingKey};
use rand::rngs::OsRng;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{path::PathBuf, sync::Arc};
use tokio::sync::RwLock;

pub const STARTER_TOKENS: i64   = 100;
pub const MAX_BALANCE: i64      = 10_000;
pub const TOKENS_PER_1K: i64   = 10;
pub const TOKENS_PER_HOUR: i64 = 1;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Receipt {
    pub id:          String,
    pub timestamp:   i64,
    pub provider_id: String,
    pub consumer_id: String,
    pub amount:      i64,
    pub memo:        String,
    pub signature:   String, // hex-encoded Ed25519 sig
}

impl Receipt {
    pub fn signable(&self) -> String {
        format!(
            "{}|{}|{}|{}|{}|{}",
            self.id, self.timestamp, self.provider_id,
            self.consumer_id, self.amount, self.memo
        )
    }
}

#[derive(Debug, Serialize, Deserialize)]
struct WalletData {
    node_id:        String,
    signing_key_hex: String,
    balance:        i64,
    earned_total:   i64,
    spent_total:    i64,
    receipts:       Vec<Receipt>,
}

#[derive(Clone)]
pub struct Wallet(Arc<RwLock<WalletInner>>);

struct WalletInner {
    data:        WalletData,
    signing_key: SigningKey,
    path:        PathBuf,
}

impl Wallet {
    pub async fn load_or_create(path: &str) -> Result<Self> {
        let path = shellexpand::tilde(path).to_string();
        let path = PathBuf::from(&path);

        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent).await.ok();
        }

        let (data, signing_key) = if path.exists() {
            let raw = tokio::fs::read_to_string(&path).await
                .context("Cannot read wallet")?;
            let data: WalletData = serde_json::from_str(&raw)
                .context("Cannot parse wallet")?;
            let key_bytes = hex::decode(&data.signing_key_hex)?;
            let key_arr: [u8; 32] = key_bytes.try_into()
                .map_err(|_| anyhow::anyhow!("Invalid key length"))?;
            let key = SigningKey::from_bytes(&key_arr);
            (data, key)
        } else {
            let mut csprng = OsRng;
            let signing_key = SigningKey::generate(&mut csprng);
            let verifying_key = signing_key.verifying_key();
            let node_id = hex::encode(Sha256::digest(verifying_key.as_bytes()));
            let data = WalletData {
                node_id,
                signing_key_hex: hex::encode(signing_key.as_bytes()),
                balance:      STARTER_TOKENS,
                earned_total: 0,
                spent_total:  0,
                receipts:     vec![],
            };
            (data, signing_key)
        };

        let inner = WalletInner { data, signing_key, path };
        let wallet = Self(Arc::new(RwLock::new(inner)));
        wallet.save().await?;
        Ok(wallet)
    }

    pub fn balance(&self) -> i64 {
        // sync peek – ok since we're in a single async context at startup
        self.0.try_read().map(|g| g.data.balance).unwrap_or(0)
    }

    pub async fn node_id(&self) -> String {
        self.0.read().await.data.node_id.clone()
    }

    pub async fn stats(&self) -> (i64, i64, i64) {
        let g = self.0.read().await;
        (g.data.balance, g.data.earned_total, g.data.spent_total)
    }

    /// Sign and record a receipt as the provider (we earned tokens)
    pub async fn record_earned(&self, consumer_id: &str, amount: i64, memo: &str) -> Result<Receipt> {
        let mut g = self.0.write().await;
        let new_bal = (g.data.balance + amount).min(MAX_BALANCE);
        let earned = amount.min(MAX_BALANCE - g.data.balance);

        let mut receipt = Receipt {
            id:          uuid::Uuid::new_v4().to_string(),
            timestamp:   Utc::now().timestamp(),
            provider_id: g.data.node_id.clone(),
            consumer_id: consumer_id.to_string(),
            amount:      earned,
            memo:        memo.to_string(),
            signature:   String::new(),
        };
        let sig = g.signing_key.sign(receipt.signable().as_bytes());
        receipt.signature = hex::encode(sig.to_bytes());

        g.data.balance      = new_bal;
        g.data.earned_total += earned;
        g.data.receipts.push(receipt.clone());
        drop(g);
        self.save().await?;
        Ok(receipt)
    }

    /// Deduct tokens for a request we made
    pub async fn spend(&self, provider_id: &str, amount: i64, memo: &str) -> Result<()> {
        let mut g = self.0.write().await;
        if g.data.balance < amount {
            anyhow::bail!("Insufficient tokens: have {}, need {}", g.data.balance, amount);
        }
        g.data.balance     -= amount;
        g.data.spent_total += amount;
        drop(g);
        self.save().await?;
        Ok(())
    }

    async fn save(&self) -> Result<()> {
        let g = self.0.read().await;
        let raw = serde_json::to_string_pretty(&g.data)?;
        tokio::fs::write(&g.path, raw).await.context("Cannot write wallet")?;
        Ok(())
    }
}
