import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "VisaProof Explorer",
  description:
    "On-chain Agent Visa qualification on Celo, gated on a Self Agent ID proof of human.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
