# Converts a CMake list to a string containing elements separated by spaces
function(PACKAGE_TO_LIST_SPACES _LIST_NAME OUTPUT_VAR)
  set(NEW_LIST_SPACE)
  foreach(ITEM ${${_LIST_NAME}})
    set(NEW_LIST_SPACE "${NEW_LIST_SPACE} ${ITEM}")
  endforeach()
  string(STRIP ${NEW_LIST_SPACE} NEW_LIST_SPACE)
  set(${OUTPUT_VAR} "${NEW_LIST_SPACE}" PARENT_SCOPE)
endfunction()


execute_process(COMMAND "date" "+%Y" OUTPUT_VARIABLE PACKAGE_BUILD_YEAR)
string(STRIP ${PACKAGE_BUILD_YEAR} PACKAGE_BUILD_YEAR)

set(PACKAGE_VER_NAME ${PACKAGE_NAME}-${PACKAGE_VERSION})
set(PACKAGE_SRC_TAR_NAME     ${PACKAGE_NAME}_${PACKAGE_VERSION}.tar.gz)

if(NOT PACKAGE_SRC_DIR)
    set(PACKAGE_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR})
endif(NOT PACKAGE_SRC_DIR)

if(EXISTS ${PACKAGE_SRC_DIR}/debian/changelog.in)
    configure_file(${PACKAGE_SRC_DIR}/debian/changelog.in
               ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_VER_NAME}/debian/changelog @ONLY)
endif()

if(EXISTS ${PACKAGE_SRC_DIR}/debian/control.in)
    configure_file(${PACKAGE_SRC_DIR}/debian/control.in
               ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_VER_NAME}/debian/control @ONLY)
endif()

if(EXISTS ${PACKAGE_SRC_DIR}/debian/copyright.in)
    configure_file(${PACKAGE_SRC_DIR}/debian/copyright.in
               ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_VER_NAME}/debian/copyright @ONLY)
endif()

if(EXISTS ${PACKAGE_SRC_DIR}/rpm/${PACKAGE_NAME}.spec.in)
    configure_file(${PACKAGE_SRC_DIR}/rpm/${PACKAGE_NAME}.spec.in
               ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_NAME}.spec @ONLY)
endif()

if(EXISTS ${PACKAGE_SRC_DIR}/arch/PKGBUILD.in)
    configure_file(${PACKAGE_SRC_DIR}/arch/PKGBUILD.in
                ${CMAKE_CURRENT_BINARY_DIR}/PKGBUILD.in @ONLY)
endif()

if(PACKAGE_ARCH_INSTALL_FILE)
    configure_file(${PACKAGE_SRC_DIR}/arch/${PACKAGE_ARCH_INSTALL_FILE}.in
                   ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_ARCH_INSTALL_FILE} @ONLY)
endif(PACKAGE_ARCH_INSTALL_FILE)

if(NOT PACKAGE_CUSTOM_SRC_PREPARE)
    add_custom_target(${PACKAGE_NAME}-src-prepare
        #копируем исходники, чтобы не засорять исходную папку результатами
        COMMAND cp -r ${CMAKE_CURRENT_SOURCE_DIR}/* ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_VER_NAME}
        COMMAND chmod +x ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_VER_NAME}/debian/rules
        COMMAND tar -caf ${PACKAGE_SRC_TAR_NAME} ${PACKAGE_VER_NAME}
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
        )
endif(NOT PACKAGE_CUSTOM_SRC_PREPARE)

# для создание порта FreeBSD необходимо определение его категории
if(PACKAGE_FREEBSD_CATEGORY)
    if(EXISTS "${PACKAGE_SRC_DIR}/FreeBSD/port")
        #имя архива делаем в соответствии с правилами FreeBSD
        set(FREEBSD_TAR_NAME  ${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz)
        #корень исходников портов, куда будет копироваться созданный порт
        if(NOT FREEBSD_PORTS_DIR)
            set(FREEBSD_PORTS_DIR $ENV{PORTSDIR})
        endif(NOT FREEBSD_PORTS_DIR)


        # подготовка файлов порта
        file(COPY "${PACKAGE_SRC_DIR}/FreeBSD/port" DESTINATION ${CMAKE_CURRENT_BINARY_DIR}/FreeBSD)

        # конфигурация Makefile и pkg-plist при необходимости
        if(EXISTS "${PACKAGE_SRC_DIR}/FreeBSD/Makefile.in")
            configure_file(${PACKAGE_SRC_DIR}/FreeBSD/Makefile.in
                           ${CMAKE_CURRENT_BINARY_DIR}/FreeBSD/port/Makefile @ONLY)
        endif()
        if(EXISTS "${PACKAGE_SRC_DIR}/FreeBSD/pkg-plist.in")
            configure_file(${PACKAGE_SRC_DIR}/FreeBSD/pkg-plist.in
                           ${CMAKE_CURRENT_BINARY_DIR}/FreeBSD/port/pkg-plist @ONLY)
        endif()
        add_custom_target(${PACKAGE_NAME}-freebsd-src-prepare
            COMMAND cp ${PACKAGE_SRC_TAR_NAME} FreeBSD/${FREEBSD_TAR_NAME}
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
            DEPENDS ${PACKAGE_NAME}-src-prepare
            )

        set(FREEBSD_PACKAGE_DST_DIR ${FREEBSD_PORTS_DIR}/${PACKAGE_FREEBSD_CATEGORY}/${PACKAGE_NAME})

        #копирование файлов порта в дерево Port Collection и создание контрольных сумм
        add_custom_target(
            ${PACKAGE_NAME}-freebsd-port-prepare
            #создаем директорию для архивов, если она не была создана, и копируем в нее архив с пакетом
            COMMAND cmake -E make_directory ${FREEBSD_PORTS_DIR}/distfiles
            COMMAND cp  ${CMAKE_CURRENT_BINARY_DIR}/FreeBSD/${FREEBSD_TAR_NAME} ${FREEBSD_PORTS_DIR}/distfiles/
            #пересоздаем директорию порта для очистки и копируем содержимое порта
            COMMAND cmake -E remove_directory ${FREEBSD_PACKAGE_DST_DIR}
            COMMAND cmake -E make_directory ${FREEBSD_PACKAGE_DST_DIR}
            COMMAND cp -r ${CMAKE_CURRENT_BINARY_DIR}/FreeBSD/port/* ${FREEBSD_PACKAGE_DST_DIR}
            #создание контрольной суммы
            COMMAND make -C ${FREEBSD_PACKAGE_DST_DIR} makesum
            DEPENDS ${PACKAGE_NAME}-freebsd-src-prepare)
    endif()
endif(PACKAGE_FREEBSD_CATEGORY)



#цель для создания бинарного deb-пакета
add_custom_target(${PACKAGE_NAME}-deb
    COMMAND debuild -us -uc
    DEPENDS ${PACKAGE_NAME}-src-prepare
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_VER_NAME}
    )
#цель для сборки deb-пакета с исходниками
add_custom_target(${PACKAGE_NAME}-deb-src
    COMMAND debuild -us -uc -S
    DEPENDS ${PACKAGE_NAME}-src-prepare
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE_VER_NAME}
    )

add_custom_target(${PACKAGE_NAME}-arch-prepare
    COMMAND cp PKGBUILD.in PKGBUILD
    COMMAND makepkg -g >> PKGBUILD
    DEPENDS ${PACKAGE_NAME}-deb-src
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    )

add_custom_target(${PACKAGE_NAME}-arch
    COMMAND cp PKGBUILD.in PKGBUILD
    COMMAND makepkg -g >> PKGBUILD
    COMMAND makepkg -f
    DEPENDS ${PACKAGE_NAME}-src-prepare
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    )



#цели для загрузки пакетов на сервер OBS (Open Build System)

set(OSC_COPY_FILES ${OSC_COPY_FILES}
        ${PACKAGE_NAME}_${PACKAGE_VERSION}.dsc
        ${PACKAGE_SRC_TAR_NAME}
        ${PACKAGE_NAME}.spec
        PKGBUILD
    )

if(PACKAGE_ARCH_INSTALL_FILE)
    set(OSC_COPY_FILES ${OSC_COPY_FILES} ${PACKAGE_ARCH_INSTALL_FILE})
endif(PACKAGE_ARCH_INSTALL_FILE)


PACKAGE_TO_LIST_SPACES(OSC_COPY_FILES OSC_COPY_FILES_STRING)


#получение текущего пакета с сервера и замена файлов
add_custom_target(${PACKAGE_NAME}-osc-prepare
    #удаляем старые файлы
    COMMAND rm -rf ${OSC_PROJECT}
    #получаем текущую версию с сервера
    #COMMAND osc checkout ${OSC_PROJECT} ${PACKAGE_NAME}
    #удаляем из нее все файлы
    COMMAND rm -rf ${OSC_PROJECT}/${PACKAGE_NAME}
    COMMAND osc checkout -M ${OSC_PROJECT} ${PACKAGE_NAME}
    COMMAND rm ${OSC_PROJECT}/${PACKAGE_NAME}/_meta
    #копируем нужные файлы
    COMMAND cp ${PACKAGE_NAME}_${PACKAGE_VERSION}.dsc ${OSC_PROJECT}/${PACKAGE_NAME}
    COMMAND cp ${PACKAGE_SRC_TAR_NAME} ${OSC_PROJECT}/${PACKAGE_NAME}
    COMMAND cp ${PACKAGE_NAME}.spec ${OSC_PROJECT}/${PACKAGE_NAME}
    COMMAND cp PKGBUILD ${OSC_PROJECT}/${PACKAGE_NAME}
    COMMAND cp ${PACKAGE_ARCH_INSTALL_FILE} ${OSC_PROJECT}/${PACKAGE_NAME} || exit 0
    DEPENDS ${PACKAGE_NAME}-deb-src
    DEPENDS ${PACKAGE_NAME}-arch-prepare
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    VERBATIM
    )
#фиксирование изменений и заливка измененного пакета на сервер
add_custom_target(${PACKAGE_NAME}-osc
    COMMAND osc addremove
    COMMAND osc commit -v -m "new version"
    DEPENDS ${PACKAGE_NAME}-osc-prepare
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/${OSC_PROJECT}/${PACKAGE_NAME}
    )
