;;; init-minibuffer.el --- Minibuffer completion and navigation -*- lexical-binding: t; -*-

;; Show the current and total match counts while incrementally searching.
(setq isearch-lazy-count t
      lazy-count-prefix-format "%s/%s "
      lazy-count-suffix-format nil)

;; Command/file completion and search.
(use-package vertico
  :if (locate-library "vertico")
  :config (vertico-mode 1))

(use-package orderless
  :if (locate-library "orderless")
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :if (locate-library "marginalia")
  :config (marginalia-mode 1))

(use-package consult
  :if (locate-library "consult")
  :bind (("C-x b" . consult-buffer)
         ("C-c f" . consult-ripgrep)
         ("C-c s" . consult-line)
         ("C-c r" . consult-recent-file)
         ("C-c T" . consult-theme)
         ("M-g i" . consult-imenu)
         ("M-g I" . consult-imenu-multi)
         ("M-g o" . consult-outline))
  :config
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref))

(use-package embark
  :if (locate-library "embark")
  :bind (("C-." . embark-act)
         ("C-;" . embark-dwim)
         ("C-h B" . embark-bindings))
  :init
  (setq prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :if (locate-library "embark-consult")
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package avy
  :if (locate-library "avy")
  :bind (("C-c j" . avy-goto-char-timer)))

(provide 'init-minibuffer)
;;; init-minibuffer.el ends here
