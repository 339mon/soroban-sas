use crate::{
    ContractPausedEvent, ContractUnpausedEvent, SASError, CONTRACT_PAUSED, CONTRACT_UNPAUSED,
};
use soroban_sdk::{panic_with_error, symbol_short, Address, Env, Symbol};

/// Shared instance-storage key used by every pausable SAS contract.
pub const PAUSED_KEY: Symbol = symbol_short!("PAUSED");

/// Reusable emergency-stop behavior for protocol contracts.
///
/// Implementors expose their own authenticated `pause` / `unpause` entry
/// points, while this trait owns the storage layout, standardized events,
/// and the write-path guard. Keeping those mechanics in one place prevents
/// the SAS core, registry, and indexer from drifting into incompatible pause
/// semantics.
pub trait Pausable {
    fn is_paused(env: &Env) -> bool {
        env.storage().instance().get(&PAUSED_KEY).unwrap_or(false)
    }

    fn set_paused(env: &Env, authorizer: &Address) {
        env.storage().instance().set(&PAUSED_KEY, &true);
        env.events().publish(
            (CONTRACT_PAUSED, authorizer.clone()),
            ContractPausedEvent {
                authorizer: authorizer.clone(),
            },
        );
    }

    fn set_unpaused(env: &Env, authorizer: &Address) {
        env.storage().instance().set(&PAUSED_KEY, &false);
        env.events().publish(
            (CONTRACT_UNPAUSED, authorizer.clone()),
            ContractUnpausedEvent {
                authorizer: authorizer.clone(),
            },
        );
    }

    fn require_not_paused(env: &Env) {
        if Self::is_paused(env) {
            panic_with_error!(env, SASError::ContractPaused);
        }
    }
}
