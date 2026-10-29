;;; init-minibuffer.el --- Minibuffer completion and navigation -*- lexical-binding: t; -*-

(declare-function consult-xref "consult.el")
(declare-function consult--frame-buffer-list "consult.el")
(declare-function consult--buffer-query "consult.el")
(declare-function consult--buffer-pair "consult.el")

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
  :bind (("C-x b" . lcw-consult-buffer)
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

(defun lcw-tab-recorded-buffers (tab)
  "Return live buffers recorded for tab-bar TAB.
The selected tab keeps this data in frame parameters; inactive tabs keep it in
their saved window configuration."
  (seq-filter
   #'buffer-live-p
   (if (eq (car tab) 'current-tab)
       (consult--frame-buffer-list)
     (append (alist-get 'wc-bl tab)
             (reverse (alist-get 'wc-bbl tab))))))

(defun lcw-tab-buffer-groups ()
  "Partition all live buffers by their membership in tab-bar workspaces.
Return an alist whose keys are `current', `shared', `other', and `unassigned'."
  (let* ((tabs (tab-bar-tabs))
         (current-tab (seq-find (lambda (tab) (eq (car tab) 'current-tab)) tabs))
         (current (delete-dups (lcw-tab-recorded-buffers current-tab)))
         (other-tabs
          (delete-dups
           (seq-mapcat (lambda (tab)
                         (unless (eq (car tab) 'current-tab)
                           (lcw-tab-recorded-buffers tab)))
                       tabs)))
         (current-set (make-hash-table :test #'eq))
         (other-set (make-hash-table :test #'eq)))
    (dolist (buffer current) (puthash buffer t current-set))
    (dolist (buffer other-tabs) (puthash buffer t other-set))
    `((current . ,(seq-remove (lambda (buffer) (gethash buffer other-set))
                              current))
      (shared . ,(seq-filter (lambda (buffer) (gethash buffer other-set))
                             current))
      (other . ,(seq-remove (lambda (buffer) (gethash buffer current-set))
                            other-tabs))
      (unassigned
       . ,(seq-remove (lambda (buffer)
                        (or (gethash buffer current-set)
                            (gethash buffer other-set)))
                      (buffer-list))))))

(defun lcw-consult-tab-buffer-source (name buffers default-buffer)
  "Build a Consult source named NAME from BUFFERS.
When DEFAULT-BUFFER is present, put it first and mark the source as default."
  (let* ((items (consult--buffer-query :sort 'visibility
                                       :buffer-list buffers
                                       :as #'consult--buffer-pair))
         (default-item
          (seq-find (lambda (item) (eq (cdr item) default-buffer)) items))
         (source (copy-sequence consult-source-buffer)))
    (when default-item
      (setq items (cons default-item (delq default-item items))))
    (setq source (plist-put source :name name)
          source (plist-put source :items items)
          source (plist-put source :default (and default-item t)))
    source))

(defun lcw-consult-buffer ()
  "Switch buffers with candidates grouped by tab-bar workspace membership."
  (interactive)
  (require 'consult)
  (let* ((groups (lcw-tab-buffer-groups))
         (default-buffer (other-buffer (current-buffer) t))
         (tab-sources
          (mapcar
           (lambda (spec)
             (lcw-consult-tab-buffer-source
              (car spec) (alist-get (cdr spec) groups) default-buffer))
           '(("Current Tab Only" . current)
             ("Shared Across Tabs" . shared)
             ("Other Tabs Only" . other)
             ("Unassigned / Background" . unassigned))))
         (other-sources (delq 'consult-source-buffer
                              (copy-sequence consult-buffer-sources))))
    (consult-buffer (append tab-sources other-sources))))

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
