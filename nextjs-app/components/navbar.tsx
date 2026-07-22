'use client'

import Link from 'next/link'
import { cn } from '@/lib/utils'

const NAV_LINKS = [
  { href: '/', label: 'Home' },
  { href: '/translate', label: 'Translate' },
]

export default function Navbar() {
  return (
    <nav className="bg-background border dark:bg-gray-900 ">
      <div className="container mx-auto flex h-16 items-center px-4">
        <Link href="/" className="text-lg font-semibold text-blue-800">
          Translate
        </Link>
        <div className=" flex flex-1 justify-center gap-6">
          {NAV_LINKS.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className={cn(
                'text-sm font-medium transition-colors hover:text-foreground/80',
                'text-foreground/60'
              )}
            >
              {link.label}
            </Link>
          ))}
        </div>
      </div>
    </nav>
  )
}
