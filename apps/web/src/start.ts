import { accountAvMiddleware } from "@avalsys/account-av-web";
import { createStart } from "@tanstack/react-start";

export const startInstance = createStart(() => ({
  requestMiddleware: [accountAvMiddleware()]
}));
