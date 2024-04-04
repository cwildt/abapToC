CLASS zcl_zabap_toc DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS:
      create IMPORTING source_transport TYPE trkorr target_system TYPE tr_target RETURNING VALUE(toc) TYPE trkorr RAISING zcx_zabap_exception,
      release IMPORTING toc TYPE trkorr RAISING zcx_zabap_exception,
      import IMPORTING toc TYPE trkorr target_system TYPE tr_target RETURNING VALUE(ret_code) TYPE trretcode RAISING zcx_zabap_exception,
      import_objects IMPORTING source_transport TYPE trkorr destination_transport TYPE trkorr RAISING zcx_zabap_exception,
      check_status_in_system IMPORTING toc TYPE trkorr system TYPE tr_target EXPORTING imported TYPE abap_bool rc TYPE i RAISING zcx_zabap_exception.

  PRIVATE SECTION.
    DATA c_transport_type_toc TYPE trfunction VALUE 'T'.

    METHODS get_toc_description IMPORTING source_transport TYPE trkorr RETURNING VALUE(description) TYPE string.
ENDCLASS.


CLASS zcl_zabap_toc IMPLEMENTATION.
  METHOD check_status_in_system.
    DATA:
      settings TYPE ctslg_settings,
      cofiles  TYPE ctslg_cofile.

    APPEND system TO settings-systems.

    CALL FUNCTION 'TR_READ_GLOBAL_INFO_OF_REQUEST'
      EXPORTING
        iv_trkorr   = toc
        is_settings = settings
      IMPORTING
        es_cofile   = cofiles.

    IF cofiles-exists = abap_false.
      RAISE EXCEPTION TYPE zcx_zabap_exception EXPORTING message = CONV #( text-e05 ) .
    ENDIF.

    imported = cofiles-imported.
    rc = cofiles-rc.
  ENDMETHOD.

  METHOD create.
    TRY.
        cl_adt_cts_management=>create_empty_request( EXPORTING iv_type = 'T' iv_text = CONV #( get_toc_description( source_transport ) )
                                               iv_target = target_system IMPORTING es_request_header = DATA(transport_header) ).
        import_objects( source_transport = source_transport destination_transport = transport_header-trkorr ).
        toc = transport_header-trkorr.

      CATCH cx_root INTO DATA(cx).
        RAISE EXCEPTION TYPE zcx_zabap_exception EXPORTING message = replace( val = text-e01 sub = '&1' with = cx->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD import.

    DATA error TYPE string.
    DATA msgv1 TYPE sy-msgv1.
    DATA msgv2 TYPE sy-msgv2.
    DATA targets TYPE trsysclis.
    DATA index TYPE sy-tabix.
    DATA rfc_subrc TYPE sy-subrc.
    DATA exit TYPE char1.
    DATA selfield TYPE slis_selfield.
    DATA fieldcat TYPE slis_t_fieldcat_alv.

    CALL FUNCTION 'TR_GET_LIST_OF_TARGETS'
      EXPORTING
        iv_cons_target       = target_system
        iv_follow_deliveries = abap_false
      IMPORTING
        et_targets           = targets    " Table of Simple Transport Targets
      EXCEPTIONS
        tce_config_error     = 1
        OTHERS               = 2.
    IF sy-subrc <> 0.
      error = |No target systems found for { target_system }|.
    ENDIF.

    IF targets IS NOT INITIAL.
      IF lines( targets ) = 1.

        index = 1.

      ELSE.

        CALL FUNCTION 'REUSE_ALV_FIELDCATALOG_MERGE'
          EXPORTING
            i_structure_name       = 'TRSYSCLI'
          CHANGING
            ct_fieldcat            = fieldcat
          EXCEPTIONS
            inconsistent_interface = 1
            program_error          = 2
            OTHERS                 = 3.

        IF sy-subrc <> 0. "should never be
          MESSAGE ID sy-msgid TYPE 'E' NUMBER sy-msgno
                  WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
        ENDIF.

        APPEND INITIAL LINE TO fieldcat REFERENCE INTO DATA(field).
        field->checkbox = abap_true.
        field->fieldname = 'SELECTED'.

        CALL FUNCTION 'REUSE_ALV_POPUP_TO_SELECT'
          EXPORTING
            i_title          = 'Select Transport Targets'
            i_tabname        = 'TRSYSCLIS'
            i_structure_name = 'TRSYSCLI'
          IMPORTING
            es_selfield      = selfield
            e_exit           = exit
          TABLES
            t_outtab         = targets
          EXCEPTIONS
            program_error    = 1
            OTHERS           = 2.
        IF sy-subrc <> 0.
          RETURN.
        ENDIF.
        IF exit = abap_true.
          RETURN.
        ENDIF.
        index = selfield-tabindex.
      ENDIF.

      DATA(target) = targets[ index ].
      DATA target_rfc_destination TYPE rscat-rfcdest.
      target_rfc_destination = |{ target-sysname }.{ target-client }|.

      CALL FUNCTION 'CAT_CHECK_RFC_DESTINATION'
        EXPORTING
          rfcdestination = target_rfc_destination    " System to be tested
        IMPORTING
          msgv1          = msgv1    " first part of a possible error message
          msgv2          = msgv2    " second part of a possible error message
          rfc_subrc      = rfc_subrc.    " Return code: 0=OK;1=No Dest;2=Comm.err;3=Sys.Err

      IF sy-subrc = 0.

        CALL FUNCTION 'ZABAP_TOC_UNPACK' DESTINATION target_rfc_destination
          EXPORTING
            toc           = toc
            target_system = target_rfc_destination
          IMPORTING
            ret_code      = ret_code
            error         = error.
        IF strlen( error ) > 0.
          RAISE EXCEPTION TYPE zcx_zabap_exception
            EXPORTING
              message = replace( val = text-e03 sub = '&1' with = error ).
        ENDIF.
      ELSE.
        error = |{ msgv1 } { msgv2 }|.
      ENDIF.
    ENDIF.

  ENDMETHOD.

  METHOD import_objects.
    DATA request_headers TYPE trwbo_request_headers.
    DATA requests        TYPE trwbo_requests.

    CALL FUNCTION 'TR_READ_REQUEST_WITH_TASKS'
      EXPORTING
        iv_trkorr          = source_transport
      IMPORTING
        et_request_headers = request_headers
        et_requests        = requests
      EXCEPTIONS
        invalid_input      = 1
        OTHERS             = 2.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_zabap_exception
        EXPORTING
          message = replace( val = replace( val = text-e01 sub = '&1' with = |{ sy-subrc }| ) sub = '&2' with = 'TR_READ_REQUEST_WITH_TASKS' ).
    ENDIF.

    LOOP AT request_headers REFERENCE INTO DATA(request_header) WHERE trkorr = source_transport OR strkorr = source_transport.
      CALL FUNCTION 'TR_COPY_COMM'
        EXPORTING
          wi_dialog                = abap_false
          wi_trkorr_from           = request_header->trkorr
          wi_trkorr_to             = destination_transport
          wi_without_documentation = abap_false
        EXCEPTIONS
          db_access_error          = 1                " Database access error
          trkorr_from_not_exist    = 2                " first correction does not exist
          trkorr_to_is_repair      = 3                " Target correction is repair
          trkorr_to_locked         = 4                " Command file TRKORR_TO blocked, (SM12)
          trkorr_to_not_exist      = 5                " second correction does not exist
          trkorr_to_released       = 6                " second correction already released
          user_not_owner           = 7                " User is not owner of first request
          no_authorization         = 8                " No authorization for this function
          wrong_client             = 9                " Different clients (source - target)
          wrong_category           = 10               " Different category (source - target)
          object_not_patchable     = 11
          OTHERS                   = 12.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zcx_zabap_exception
          EXPORTING
            message = replace( val = replace( val = text-e01 sub = '&1' with = |{ sy-subrc }| ) sub = '&2' with = 'TR_COPY_COMM' ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD release.
    TRY.
        DATA(cts_api) = cl_cts_rest_api_factory=>create_instance( ).
        cts_api->release( iv_trkorr = toc iv_ignore_locks = abap_true ).

      CATCH cx_root INTO DATA(cx).
        RAISE EXCEPTION TYPE zcx_zabap_exception EXPORTING message = replace( val = text-e02 sub = '&1' with = cx->get_text( ) ).
    ENDTRY.
  ENDMETHOD.

  METHOD get_toc_description.
    SELECT SINGLE as4text FROM e07t
      INTO @DATA(as4text)
      WHERE trkorr = @source_transport
        AND langu = @sy-langu.

    IF sy-subrc <> 0.

      SELECT SINGLE as4text FROM e07t
        INTO @as4text
        WHERE trkorr = @source_transport.

    ENDIF.

    description = replace( val  = text-t01
                           sub  = '&1'
                           with = |{ source_transport } { as4text }| ).
  ENDMETHOD.

ENDCLASS.
