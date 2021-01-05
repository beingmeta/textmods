;;; -*- Mode: scheme; Character-encoding: utf-8; -*-

(in-module 'booktools/gutdb)

(use-module '{texttools webtools logger domutils domutils/index varconfig binio})

(define-init %loglevel %notify%)

(define gutcache (make-hashtable))
(define gutindex #f)
(varconfig! gutindex gutindex file->dtype)
(define gutserver #f)
(varconfig! gutserver gutserver config:boolean)
(define gutlocal "/data/misc/gutenberg/epub/")
(varconfig! gutlocal gutlocal)

(module-export! '{gutdb gutdb/rdf})

(define (gutdb/rdf id)
  (try (tryif (and gutlocal (file-exists? (mkpath gutlocal (glom id "/pg" id ".rdf"))))
	 (xmlparse (filestring (mkpath gutlocal (glom id "/pg" id ".rdf")))))
       (tryif (and gutlocal (file-exists? (mkpath gutlocal (glom id "/pg" id ".rdf"))))
	 (xmlparse (filestring (mkpath gutlocal (glom id "/pg" id ".rdf")))))
       (tryif gutserver
	 (let* ((url (stringout "http://www.gutenberg.org/cache/epub/"
		       id "/pg" id ".rdf"))
		(response (and url (urlget url)))
		(seen {}))
	   (when response
	     (while (and (test response 'location)
			 (not (overlaps? (get response 'location) seen)))
	       (debug%watch "GUTDB/RDF redirect" url)
	       (set+! seen (get response 'location))
	       (set! url  (get response 'location))
	       (set! response (urlget (get response 'location))))
	     (debug%watch "GUTDB/RDF fetched" url))
	   (and response (xmlparse (get response '%content)))))))

(define (gutdb-inner arg)
  (if (or (string? arg) (number? arg))
      (handle-rdf (gutdb/rdf arg))
      (and (table? arg) (handle-rdf arg))))
(define (gutdb arg)
  (try (tryif gutindex
	 (try (get gutindex arg)
	      (tryif (string? arg)
		(get gutindex (string->number arg)))))
       (tryif (or gutlocal gutserver)
	 (cachecall gutcache gutdb-inner arg))))

(define (nodetext n) (decode-entities (xmlcontent n)))
(define (subjtext n (slotid #f))
  (let ((text (decode-entities
	       (if slotid (get (get n slotid) 'value)
		   (difference (xmlcontent n) "")))))
    (tryif (exists? text)
      (if (textsearch #((spaces) "--" (spaces)) text)
	  (textslice text #((spaces) "--" (spaces)) #f)
	  text))))
(define (subjsplit text)
  (if (textsearch #((spaces) "--" (spaces)) text)
      (textslice text #((spaces) "--" (spaces)) #f)
      text))
(define (rightstext n)
  (if (string? n) (decode-entities n)
      (if (test n 'resource) (get n 'resource)
	  (decode-entities (xmlcontent n)))))
(define (getvals x slot)
  (choice (reject (get x slot) 'bag)
	  (get (get (get x slot) 'bag) 'li)))
(define (getresource x) (get x '{resource rdf:resource}))
(define (get-member-of x)
  (get (xmlget x 'memberof) 'rdf:resource))

(define (handle-rdf rdf)
  (let ((info (frame-create #f))
	(index (make-hashtable)))
    (dom/index! index rdf)
    (do-choices (field '{title rights publisher})
      (add! info field (nodetext (xmlget rdf field))))
    (do-choices (field '{(creator . creator)
			 (trl . translator)
			 (ctb . contributor)})
      (do-choices (value (xmlget rdf (car field)))
	(let* ((about (get value 'resource))
	       (ref (try (find-frames index '{about rdf:about} about)
			 value))
	       (sum (frame-create #f)))
	  (when (exists? value)
	    (do-choices (slotid '{name webpage alias birthdate deathdate})
	      (when (exists? (xmlget ref slotid))
		(store! sum slotid
			(difference ({xmlcontent getresource} (xmlget ref slotid)) ""))))
	    (store! info (cdr field) sum))))
      (do-choices (subject (xmlget rdf 'subject))
	(let ((type (get-member-of subject))
	      (values (xmlcontent (xmlget subject 'value))))
	  (cond ((equal? type "http://purl.org/dc/terms/LCSH")
		 (store! info 'lcsh (subjsplit values)))
		((equal? type "http://purl.org/dc/terms/LCC")
		 (store! info 'lcc values))))))
    (add! info 'files (get (xmlget rdf 'file) 'about))
    info))

(define (handle-bulk-rdf rdf)
  (let ((info (frame-create #f))
	(index (make-hashtable)))
    (dom/index! index rdf)
    (do-choices (field '{title rights publisher})
      (add! info field (nodetext (xmlget rdf field))))
    (do-choices (field '{(creator . creator)
			 (trl . translator)
			 (ctb . contributor)})
      (do-choices (value (xmlget rdf (car field)))
	(let* ((about (get value 'resource))
	       (ref (find-frames index '{about rdf:about} about))
	       (sum (frame-create #f)))
	  (when (exists? value)
	    (do-choices (slotid '{name webpage alias birthdate deathdate})
	      (when (exists? (xmlget ref slotid))
		(store! sum slotid (difference ({xmlcontent getresource} (xmlget ref slotid)) ""))))
	    (store! info (cdr field) sum))))
      (do-choices (subject (xmlget rdf 'subject))
	(let ((type (get-member-of subject))
	      (values (xmlcontent (xmlget subject 'value))))
	  (cond ((equal? type "http://purl.org/dc/terms/LCSH")
		 (store! info 'lcsh (subjsplit values)))
		((equal? type "http://purl.org/dc/terms/LCC")
		 (store! info 'lcc values))))))
    (add! info 'files (get (xmlget rdf 'file) 'about))
    info))