;;; init-dashboard.el --- Startup screen -*- lexical-binding: t; -*-

;; The startup screen replaces the classic splash.  `lcw-restore-desktop'
;; (owned by init-project, which loads earlier) powers the Restore button.

;; A normal start (no file argument) opens this dashboard instead of the last
;; session.  `R', or the Restore button, brings the previous session back
;; through `lcw-restore-desktop' in init-project.el.
(use-package dashboard
  :if (locate-library "dashboard")
  :custom
  (dashboard-startup-banner 'official)
  (dashboard-banner-logo-title nil)
  (dashboard-center-content t)
  (dashboard-vertically-center-content t)
  (dashboard-icon-type 'nerd-icons)
  (dashboard-display-icons-p t)
  (dashboard-set-heading-icons t)
  (dashboard-set-file-icons t)
  (dashboard-footer-messages '("R restore session  ·  r recent files  ·  p projects  ·  q close"))
  (dashboard-startupify-list
   '(dashboard-insert-banner
     dashboard-insert-newline
     dashboard-insert-banner-title
     dashboard-insert-newline
     dashboard-insert-navigator
     dashboard-insert-newline
     dashboard-insert-init-info
     dashboard-insert-items
     dashboard-insert-newline
     dashboard-insert-footer))
  (dashboard-init-info
   (lambda () (format "%s · %d packages" emacs-version (length package-alist))))
  (dashboard-items '((recents . 6) (projects . 4)))
  :config
  (require 'nerd-icons nil t)
  (setq dashboard-navigator-buttons
        `(((,(nerd-icons-octicon "nf-oct-history") "Restore"
            "Restore the session saved by the previous Emacs (R)"
            lcw-restore-desktop))))
  (keymap-set dashboard-mode-map "R" #'lcw-restore-desktop)
  (keymap-set dashboard-mode-map "q" #'quit-window)
  (dashboard-setup-startup-hook))

(provide (quote init-dashboard))
;;; init-dashboard.el ends here
