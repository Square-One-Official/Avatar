/* eslint-disable @typescript-eslint/no-explicit-any */
import config from "@payload-config";
import { RootLayout } from "@payloadcms/next/layouts";
import { importMap } from "./admin/importMap.js";
import "@payloadcms/next/css";

/**
 * Payload v3 admin shell. The component form (`<RootLayout>...`)
 * lets Payload set up its own server-function client internally
 * — bypassing the need to wire `handleServerFunctions` ourselves
 * and avoiding the import-not-exported breakage on this Payload
 * version.
 */
const Layout = ({ children }: { children: React.ReactNode }) => (
  <RootLayout config={config} importMap={importMap}>
    {children}
  </RootLayout>
);

export default Layout;
