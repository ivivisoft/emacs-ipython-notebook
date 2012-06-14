;;; ein-notebooklist.el --- Notebook list buffer

;; Copyright (C) 2012- Takafumi Arakaki

;; Author: Takafumi Arakaki

;; This file is NOT part of GNU Emacs.

;; ein-notebooklist.el is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; ein-notebooklist.el is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ein-notebooklist.el.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(eval-when-compile (require 'cl))
(require 'widget)

(require 'ein-utils)
(require 'ein-notebook)
(require 'ein-subpackages)

(defstruct ein:$notebooklist
  "Hold notebooklist variables.

`ein:$notebooklist-url-or-port'
  URL or port of IPython server.

`ein:$notebooklist-data'
  JSON data sent from the server."
  url-or-port
  data)

(ein:deflocal ein:notebooklist nil
  "Buffer local variable to store an instance of `ein:$notebooklist'.")

(defvar ein:notebooklist-buffer-name-template "*ein:notebooklist %s*")

(defvar ein:notebooklist-list nil
  "A list of opened `ein:$notebooklist'.")


(defun ein:notebooklist-url (url-or-port)
  (ein:url url-or-port "notebooks"))

(defun ein:notebooklist-new-url (url-or-port)
  (ein:url url-or-port "new"))

(defun ein:notebooklist-get-buffer (url-or-port)
  (get-buffer-create
   (format ein:notebooklist-buffer-name-template url-or-port)))

(defun ein:notebooklist-ask-url-or-port ()
  (let* ((url-or-port-list (mapcar (lambda (x) (format "%s" x))
                                   ein:url-or-port))
         (default (ein:aif (ein:pytools-get-notebook)
                      (format "%s" (ein:$notebook-url-or-port it))
                    (car url-or-port-list)))
         (url-or-port
          (completing-read "URL or port number (hit TAB to complete): "
                           url-or-port-list
                           nil nil nil nil
                           default)))
    (if (string-match "^[0-9]+$" url-or-port)
        (string-to-number url-or-port)
      url-or-port)))

;;;###autoload
(defun ein:notebooklist-open (&optional url-or-port no-popup)
  "Open notebook list buffer."
  (interactive (list (ein:notebooklist-ask-url-or-port)))
  (unless url-or-port (setq url-or-port (or (car ein:url-or-port) 8888)))
  (ein:subpackages-load)
  (let ((success
         (if no-popup
             #'ein:notebooklist-url-retrieve-callback
           (lambda (&rest args)
             (pop-to-buffer
              (apply #'ein:notebooklist-url-retrieve-callback args))))))
    (ein:query-ajax
     (ein:notebooklist-url url-or-port)
     :cache nil
     :parser #'ein:json-read
     :success (cons success url-or-port)))
  (ein:notebooklist-get-buffer url-or-port))

(defun* ein:notebooklist-url-retrieve-callback (url-or-port
                                                &key
                                                status
                                                data
                                                &allow-other-keys)
  "Called via `ein:notebooklist-open'."
  (ein:aif (plist-get status :error)
      (error "Failed to connect to server '%s'.  Got: %S"
             (ein:url url-or-port) it))
  (with-current-buffer (ein:notebooklist-get-buffer url-or-port)
    (setq ein:notebooklist
          (make-ein:$notebooklist :url-or-port url-or-port
                                  :data data))
    (add-to-list 'ein:notebooklist-list ein:notebooklist)
    (ein:notebooklist-render)
    (goto-char (point-min))
    (message "Opened notebook list at %s" url-or-port)
    (current-buffer)))

(defun ein:notebooklist-reload ()
  "Reload current Notebook list."
  (interactive)
  (ein:notebooklist-open (ein:$notebooklist-url-or-port ein:notebooklist) t))

(defun ein:notebooklist-get-data-in-body-tag (key)
  "Very ad-hoc parser to get data in body tag."
  (ignore-errors
    (save-excursion
      (goto-char (point-min))
      (search-forward "<body")
      (search-forward-regexp (format "%s=\\([^[:space:]\n]+\\)" key))
      (match-string 1))))

(defun ein:notebooklist-open-notebook (nblist notebook-id &optional name
                                              callback cbargs)
  (message "Open notebook %s." (or name notebook-id))
  (ein:notebook-open (ein:$notebooklist-url-or-port nblist) notebook-id
                     callback cbargs))

(defun ein:notebooklist-new-notebook (&optional url-or-port callback cbargs)
  "Ask server to create a new notebook and open it in a new buffer."
  (interactive (list (ein:notebooklist-ask-url-or-port)))
  (message "Creating a new notebook...")
  (unless url-or-port
    (setq url-or-port (ein:$notebooklist-url-or-port ein:notebooklist)))
  (assert url-or-port nil
          (concat "URL-OR-PORT is not given and the current buffer "
                  "is not the notebook list buffer."))
  (ein:query-ajax
   (ein:notebooklist-new-url url-or-port)
   :parser (lambda ()
             (ein:notebooklist-get-data-in-body-tag "data-notebook-id"))
   :success (cons #'ein:notebooklist-new-notebook-callback
                  (list (ein:notebooklist-get-buffer url-or-port)
                        callback cbargs))))

(defun* ein:notebooklist-new-notebook-callback (packed &key
                                                       data
                                                       &allow-other-keys)
  (let ((notebook-id data)
        (buffer (nth 0 packed))
        (callback (nth 1 packed))
        (cbargs (nth 2 packed)))
    (message "Creating a new notebook... Done.")
    (with-current-buffer buffer
      (if notebook-id
          (ein:notebooklist-open-notebook ein:notebooklist notebook-id nil
                                          callback cbargs)
        (message (concat "Oops. EIN failed to open new notebook. "
                         "Please find it in the notebook list."))
        (ein:notebooklist-reload)))))

(defun ein:notebooklist-new-notebook-with-name (name &optional url-or-port)
  "Open new notebook and rename the notebook."
  (interactive "sNotebook name: ")
  (ein:notebooklist-new-notebook
   url-or-port
   (lambda (notebook created name)
     (assert created)
     (with-current-buffer (ein:notebook-buffer notebook)
       (ein:notebook-rename-command name)))
   (list name)))

(defcustom ein:scratch-notebook-name-template "_scratch_%Y-%m-%d-%H%M%S_"
  "Template of notebook name.
This value is used from `ein:notebooklist-new-scratch-notebook'."
  :type '(string :tag "Format string")
  :group 'ein)

(defun ein:notebooklist-new-scratch-notebook ()
  "Open a notebook to try random thing."
  (interactive)
  (ein:notebooklist-new-notebook-with-name
   (format-time-string ein:scratch-notebook-name-template (current-time))
   (car ein:url-or-port)))

(defun ein:notebooklist-delete-notebook-ask (notebook-id name)
  (when (y-or-n-p (format "Delete notebook %s?" name))
    (ein:notebooklist-delete-notebook notebook-id name)))

(defun ein:notebooklist-delete-notebook (notebook-id name)
  (message "Deleting notebook %s..." name)
  (ein:query-ajax
   (ein:notebook-url-from-url-and-id
    (ein:$notebooklist-url-or-port ein:notebooklist)
    notebook-id)
   :cache nil
   :type "DELETE"
   :success (cons (lambda (packed &rest ignore)
                    (message "Deleting notebook %s... Done." (cdr packed))
                    (with-current-buffer (car packed)
                      (ein:notebooklist-reload)))
                  (cons (current-buffer) name))))

(defun ein:notebooklist-render ()
  "Render notebook list widget.
Notebook list data is passed via the buffer local variable
`ein:notebooklist-data'."
  (kill-all-local-variables)
  (let ((inhibit-read-only t))
    (erase-buffer))
  (remove-overlays)
  ;; Create notebook list
  (widget-insert "IPython Notebook list\n\n")
  (widget-create
   'link
   :notify (lambda (&rest ignore) (ein:notebooklist-new-notebook))
   "New Notebook")
  (widget-insert " ")
  (widget-create
   'link
   :notify (lambda (&rest ignore) (ein:notebooklist-reload))
   "Reload List")
  (widget-insert " ")
  (widget-create
   'link
   :notify (lambda (&rest ignore)
             (browse-url
              (ein:url (ein:$notebooklist-url-or-port ein:notebooklist))))
   "Open In Browser")
  (widget-insert "\n")
  (loop for note in (ein:$notebooklist-data ein:notebooklist)
        for name = (plist-get note :name)
        for notebook-id = (plist-get note :notebook_id)
        do (progn (widget-create
                   'link
                   :notify (lexical-let ((name name)
                                         (notebook-id notebook-id))
                             (lambda (&rest ignore)
                               (ein:notebooklist-open-notebook
                                ein:notebooklist notebook-id name)))
                   "Open")
                  (widget-insert " ")
                  (widget-create
                   'link
                   :notify (lexical-let ((name name)
                                         (notebook-id notebook-id))
                             (lambda (&rest ignore)
                               (ein:notebooklist-delete-notebook-ask
                                notebook-id
                                name)))
                   "Delete")
                  (widget-insert " : " name)
                  (widget-insert "\n")))
  (ein:notebooklist-mode)
  (widget-setup))

(defun ein:notebooklist-open-notebook-global (nbpath)
  "Choose notebook from all opened notebook list and open it."
  (interactive
   (list (completing-read
          "Open notebook [URL-OR-PORT/NAME]: "
          (apply #'append
                 (loop for nblist in ein:notebooklist-list
                       for url-or-port = (ein:$notebooklist-url-or-port nblist)
                       collect
                       (loop for note in (ein:$notebooklist-data nblist)
                             collect (format "%s/%s"
                                             url-or-port
                                             (plist-get note :name))))))))
  (let* ((path (split-string nbpath "/"))
         (url-or-port (car path))
         (name (cadr path)))
    (when (and (stringp url-or-port)
               (string-match "^[0-9]+$" url-or-port))
      (setq url-or-port (string-to-number url-or-port)))
    (let ((notebook-id
           (loop for nblist in ein:notebooklist-list
                 if (loop for note in (ein:$notebooklist-data nblist)
                          when (equal (plist-get note :name) name)
                          return (plist-get note :notebook_id))
                 return it)))
      (if notebook-id
          (ein:notebook-open url-or-port notebook-id)
        (message "Notebook '%s' not found" nbpath)))))


;;; Notebook list mode

(define-derived-mode ein:notebooklist-mode fundamental-mode "ein:notebooklist"
  "IPython notebook list mode.")

(defun ein:notebooklist-prev-item () (interactive) (move-beginning-of-line 0))
(defun ein:notebooklist-next-item () (interactive) (move-beginning-of-line 2))

(setq ein:notebooklist-mode-map (copy-keymap widget-keymap))

(let ((map ein:notebooklist-mode-map))
  (define-key map "\C-c\C-r" 'ein:notebooklist-reload)
  (define-key map "g" 'ein:notebooklist-reload)
  (define-key map "p" 'ein:notebooklist-prev-item)
  (define-key map "n" 'ein:notebooklist-next-item)
  (define-key map "q" 'bury-buffer)
  map)

(provide 'ein-notebooklist)

;;; ein-notebooklist.el ends here
