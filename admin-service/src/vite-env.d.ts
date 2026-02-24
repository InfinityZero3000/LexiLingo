/// <reference types="vite/client" />

/* Google Identity Services (GSI) */
interface CredentialResponse {
  credential: string;
  select_by: string;
  clientId: string;
}

interface GsiButtonConfiguration {
  type?: "standard" | "icon";
  theme?: "outline" | "filled_blue" | "filled_black";
  size?: "large" | "medium" | "small";
  text?: "signin_with" | "signup_with" | "continue_with" | "signin";
  shape?: "rectangular" | "pill" | "circle" | "square";
  logo_alignment?: "left" | "center";
  width?: string | number;
  locale?: string;
}

interface GoogleAccountsId {
  initialize: (config: {
    client_id: string;
    callback: (response: CredentialResponse) => void;
    auto_select?: boolean;
    cancel_on_tap_outside?: boolean;
    context?: "signin" | "signup" | "use";
    ux_mode?: "popup" | "redirect";
    allowed_parent_origin?: string | string[];
  }) => void;
  renderButton: (parent: HTMLElement, config: GsiButtonConfiguration) => void;
  prompt: (notification?: (n: { isNotDisplayed: () => boolean }) => void) => void;
  disableAutoSelect: () => void;
  revoke: (hint: string, callback?: (done: { successful: boolean }) => void) => void;
}

interface Window {
  google?: {
    accounts: {
      id: GoogleAccountsId;
    };
  };
}
