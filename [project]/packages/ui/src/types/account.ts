/** Mirrors Enums.AccountRole in core_shared/shared/Enums.lua - keep in sync manually. */
export const AccountRole = {
  PLAYER: 0,
  VETERAN: 1,
  SUPPORTER: 2,
  MODERATOR: 3,
  ADMINISTRATOR: 4,
  RCON: 5,
  BOARD: 6,
} as const;

export type AccountRole = (typeof AccountRole)[keyof typeof AccountRole];

export interface Account {
  id: number;
  login: string;
  email: string;
  /** premiumExpiresAt is only present (non-null) when isPremium is true - see AccountService.toPublic. */
  isPremium: boolean;
  premiumExpiresAt: string | null;
  role: AccountRole;
  twoFactorEnabled: boolean;
}

export interface AuthStatus {
  authenticated: boolean;
  account: Account | null;
}

export interface RegisterAccountInput {
  login: string;
  email: string;
  password: string;
}

/** `login` accepts either a login or an email - see AccountService.login. */
export interface LoginAccountInput {
  login: string;
  password: string;
  /** A locally-stored trusted-device bypass token, if one exists - see TrustedDeviceStore.lua. */
  trustToken?: string;
}

/** "Remember me" credentials - stored locally only, never sent to the server. */
export interface SavedCredentials {
  login: string;
  password: string;
}

export interface ChangePasswordInput {
  currentPassword: string;
  newPassword: string;
}

export interface VerifyTwoFactorInput {
  code: string;
  /** Whether to issue a trusted-device bypass token on success. Default off - mirrors "remember me"'s own default-off pattern. */
  trustDevice: boolean;
}

export interface VerifyTwoFactorResult {
  account: Account;
  /** Present only when the request opted in via trustDevice=true AND issuing one succeeded. */
  trustToken?: string;
}

export interface EnableTwoFactorResult {
  secret: string;
  otpauthUri: string;
}

export interface ConfirmTwoFactorSetupInput {
  code: string;
}

export interface DisableTwoFactorInput {
  currentPassword: string;
}
