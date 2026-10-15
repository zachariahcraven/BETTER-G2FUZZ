// xml_fuzzer: G2Fuzz target that parses one plain XML file with libxml2 (libFuzzer interface,
// run by AFL++ as `xml_fuzzer.afl <file>`), then serializes the tree, like Chromium's
// libxml2_xml_read_memory_fuzzer. No network or external files are loaded.
#include <stddef.h>
#include <stdint.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xmlerror.h>

static void ignore_error(void *ctx, const xmlError *err) { (void)ctx; (void)err; }

int LLVMFuzzerInitialize(int *argc, char ***argv) {
  (void)argc; (void)argv;
  xmlInitParser();
  xmlSetStructuredErrorFunc(NULL, ignore_error);
  return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size > (1 << 20)) return 0;
  xmlDocPtr doc = xmlReadMemory((const char *)data, (int)size, "input.xml", NULL,
                                XML_PARSE_NONET | XML_PARSE_NOENT | XML_PARSE_DTDATTR);
  if (doc) {
    xmlChar *buf = NULL;
    int len = 0;
    xmlDocDumpMemory(doc, &buf, &len);
    xmlFree(buf);
    xmlFreeDoc(doc);
  }
  return 0;
}
