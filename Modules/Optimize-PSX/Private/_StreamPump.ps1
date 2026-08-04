# =====================================================================
# _StreamPump.ps1 - Runspace-free reader for child process output
#
# Loaded immediately after _Config.ps1 and before any function that
# starts a chdman process.
#
# WHY THIS EXISTS
#
# The obvious way to drain a redirected stream is to hand a script block
# to Process.OutputDataReceived. That does not work. PowerShell converts
# the script block into a DataReceivedEventHandler delegate, but the
# delegate is invoked on the .NET thread-pool thread owned by
# AsyncStreamReader, which has no runspace attached. The first line the
# child writes therefore throws
#
#   PSInvalidOperationException: There is no Runspace available to run
#   scripts in this thread.
#
# and because it is thrown on a thread-pool thread rather than the
# pipeline thread, it is unhandled and terminates the entire PowerShell
# process with 0xE0434352.
#
# Register-ObjectEvent avoids the crash by marshalling the callback onto
# an event-processing runspace, but that runspace cannot see module-scope
# state, and the marshalling latency makes it unsuitable for a stream
# that updates several times a second.
#
# The resolution is to keep PowerShell off the callback path entirely.
# The pump below is compiled C#, so the reader threads never need a
# runspace, and it deposits lines into a ConcurrentQueue that the
# pipeline thread drains at its own pace.
#
# LINE SPLITTING
#
# chdman reports progress by rewriting one line with a bare carriage
# return and no line feed. StreamReader.ReadLine treats a lone CR as a
# terminator, but it must first see the following character to know the
# CR was not half of a CRLF pair, so the last progress update sits in the
# reader until more output arrives. During the long quiet stretch at the
# end of a large compression that stalls the progress bar.
#
# ReadBlock is used instead, splitting on CR or LF as the characters
# arrive. Whatever has been buffered is flushed on every terminator, so
# progress surfaces as soon as chdman emits it.
# =====================================================================

if (-not ('Optimize.PSX.StreamPump' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Text;
using System.Threading.Tasks;

namespace Optimize.PSX
{
    public static class StreamPump
    {
        /// <summary>
        /// Reads <paramref name="reader"/> to end on a thread-pool thread,
        /// enqueueing each carriage-return- or line-feed-delimited chunk.
        /// </summary>
        public static Task Drain(TextReader reader, ConcurrentQueue<string> queue)
        {
            if (reader == null) throw new ArgumentNullException("reader");
            if (queue == null) throw new ArgumentNullException("queue");

            return Task.Run(() =>
            {
                char[] buffer = new char[4096];
                StringBuilder pending = new StringBuilder(256);

                try
                {
                    int read;
                    while ((read = reader.ReadBlock(buffer, 0, buffer.Length)) > 0)
                    {
                        for (int i = 0; i < read; i++)
                        {
                            char c = buffer[i];

                            if (c == '\r' || c == '\n')
                            {
                                // Empty chunks are the second half of a CRLF
                                // pair, or blank output. Neither is useful.
                                if (pending.Length > 0)
                                {
                                    queue.Enqueue(pending.ToString());
                                    pending.Clear();
                                }
                            }
                            else
                            {
                                pending.Append(c);
                            }
                        }
                    }
                }
                catch (IOException)
                {
                    // The pipe closed under us, which is what a killed child
                    // process looks like from here.
                }
                catch (ObjectDisposedException)
                {
                    // Same, when the Process object was disposed first.
                }

                // A final line with no terminator is still output.
                if (pending.Length > 0)
                {
                    queue.Enqueue(pending.ToString());
                }
            });
        }
    }
}
'@
}
