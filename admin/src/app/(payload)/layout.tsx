/* eslint-disable @typescript-eslint/no-explicit-any */
import config from "@payload-config";
import { RootLayout } from "@payloadcms/next/layouts";
import { importMap } from "./admin/importMap.js";
import "@payloadcms/next/css";

const Layout = ({ children }: { children: React.ReactNode }) =>
  RootLayout({ children, config, importMap });

export default Layout;
