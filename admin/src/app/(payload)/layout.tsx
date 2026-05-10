/* eslint-disable @typescript-eslint/no-explicit-any */
import config from "@payload-config";
import "@payloadcms/next/css";
import { handleServerFunctions, RootLayout } from "@payloadcms/next/utilities";
import type { ServerFunctionClient } from "payload";
import { importMap } from "./admin/importMap.js";

/**
 * Payload v3 admin shell. Mirrors Payload's official template — both
 * `handleServerFunctions` and `RootLayout` come from
 * `@payloadcms/next/utilities`. The serverFunction client wraps
 * Payload's internal handler so the admin UI can invoke server-only
 * actions (login, document mutations, server-rendered fields).
 */
const serverFunction: ServerFunctionClient = async function (args) {
  "use server";
  return handleServerFunctions({
    ...args,
    config,
    importMap,
  });
};

const Layout = ({ children }: { children: React.ReactNode }) => (
  <RootLayout config={config} importMap={importMap} serverFunction={serverFunction}>
    {children}
  </RootLayout>
);

export default Layout;
