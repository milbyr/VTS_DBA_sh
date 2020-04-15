#!/usr/bin/velocity-python3.5
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
#  Function:  Provide LVM snapshot information and status. Could be used for check_MK.                  #
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
# Date     Who          Description                                                                     #
# 20200204 milbyr       Created.                                                                        #
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - #
#

import sys
try:
  import subprocess
except ImportError:
  sys.exit(0)

G_DEBUG=False



def FN_DEBUG(argv=""):
    ## if G_DEBUG=True then print out the text ##
    if G_DEBUG == True:
        print(argv)
    ### End of FN_DEBUG ###


def FN_VALUE_CHECK( in_value="1", g_status=0, G_IN_WARNING=75, G_IN_CRITICAL=90 ):
    ## check to see if value is outside of the warning or critical values ##

    FN_DEBUG( "FN_VALUE_CHECK:  in_value = "+ str(in_value) +" g_status = " +str(g_status) )
    if  g_status < 2 :
        if in_value >= str(G_IN_CRITICAL) :
            g_status = 2

        if g_status == 0 and in_value >= str(G_IN_WARNING)  and in_value <= str(G_IN_CRITICAL) :
            g_status=1

    FN_DEBUG( "FN_VALUE_CHECK:  in_value = "+ str(in_value) +" g_status = " +str(g_status) )
    return g_status

    ### End of FN_VALUE_CHECK ##


def FN_VG_get():
    ## return a list of VGs ##
    stdout,stderr = subprocess.Popen(['/usr/sbin/vgs', '--noheading','-o', 'vg_name' ], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()
    
    vgs = stdout.decode("utf-8").strip().replace("\t", "").replace(" ", "")
    vgs = vgs.split('\n')
    return vgs
    ### End of FN_VG_get ###


def FN_LV_header():
    l_lv_header = ('lv_name','lv_size','data_percent','metadata_percent','snap_percent','lv_when_full','time','lv_descendants','origin','lv_attr')
    print( l_lv_header )
    ### End of FN_LV_header ###    


def FN_LV_get( arg1 = 'dbP001'):
    stdout,stderr = subprocess.Popen(['/usr/sbin/lvs', arg1, '--noheading','-o',\
    'lv_name,lv_size,data_percent,metadata_percent,snap_percent,lv_when_full,time,lv_descendants,origin,lv_attr', \
    '--separator', '|', '-O', 'lv_name', '-S', 'lv_attr=~[^Vwi]'], stdout=subprocess.PIPE, stderr=subprocess.STDOUT).communicate()
    
    lvs = stdout.decode("utf-8").strip().replace("\t", "").replace(" ", "")
    lvs = lvs.split('\n')
    
    mylisttuple = [tuple(map(str, i.split('|'))) for i in lvs]
    ## print( mylisttuple )
    return  mylisttuple 
    ### End of FN_LV_get ###


def  FN_LV_snap_tree (arg_vg, arg_lv, G_LV_LIST_TUPLE, arg_t_lvl, g_status, g_processed, G_IN_WARNING, G_IN_CRITICAL):
    ## walk the snapshot tree to reach the leaf nodes ##

    ## check if the arg_lv has already been processed
    if arg_lv not in g_processed:
        arg_t_lvl += 1
        FN_DEBUG('lv not in g_processed')
        g_processed.append(arg_lv)
        #print( "I'm here with arg_lv="+arg_lv)
        #print(G_LV_LIST_TUPLE)
        ###        i=0
        ###        for mytuple in G_LV_LIST_TUPLE:
        ###            print( "index="+str(i)+ " type="+str(mytuple[0]) )
        ###            i += 1
        ###            if mytuple[0] == arg_lv:
        ###                L_LIST_IND = i
        ###
        L_LIST_IND = [i for i, tupl in enumerate(G_LV_LIST_TUPLE) if tupl[0] == arg_lv]
        FN_DEBUG( "index=" + str(L_LIST_IND[0]) )
        ## print out the tuple
        #print( "test list_tuple[" + str(L_LIST_IND) + "]=" + str(G_LV_LIST_TUPLE[ L_LIST_IND ] ) ) 
        FN_DEBUG( "FN_LV_snap_tree: list_tuple[" + str(L_LIST_IND[0]) + "]=" + str(G_LV_LIST_TUPLE[ L_LIST_IND[0] ] ) ) 

        (lv_name,lv_size,data_percent,metadata_percent,snap_percent,lv_when_full,time,lv_descendants,origin,lv_attr)=G_LV_LIST_TUPLE[L_LIST_IND[0]]
        for ind in range(arg_t_lvl):
            print("    ",  end=' ')

        ## tuple template: lvtechst_D003_20200124_1014    size=20.00g data=39.96% snap=39.96% meta=0% action_when_full=>< timesstamp=2020-01-2410:16:12+0000 g_status=2 ##

        print("%-20s : lv_size=%s data_pct=%s snap_pct=%s " % (lv_name, lv_size, data_percent, snap_percent ))
        #print("%-20s : lv_size=%s data_pct=%s snap_pct=%s action_when_full=>%s<" % (lv_name, lv_size, data_percent, snap_percent , action_when_full))

        ## check the PCT values to see if they breach the G_WARNING or G_CRITICAL thresholds
        #for l_val in data_percent, snap_percent, metadata_percent ;
        for l_val in data_percent, snap_percent :
              g_status = FN_VALUE_CHECK( l_val, g_status, G_IN_WARNING, G_IN_CRITICAL )
        if lv_descendants != "" :
            ## increase the indentation
            #g_level += 1
            #G_IND_STR = G_IND_STR + "    "
            FN_DEBUG( "FN_LV_snap_tree: lv_descendants = " + lv_descendants )
            L_DESC_LIST=lv_descendants.split(",")
            FN_DEBUG( "L_DESC_LIST="+str(L_DESC_LIST) )
            for lv_branch in L_DESC_LIST :
                 FN_DEBUG( "FN_LV_snap_tree: processing " + str(lv_branch ) )
                 g_status = FN_LV_snap_tree( arg_vg, lv_branch, G_LV_LIST_TUPLE, arg_t_lvl, g_status, g_processed, G_IN_WARNING, G_IN_CRITICAL)

        FN_DEBUG("- - - - - - - - - - ")

    return g_status

    ### End of FN_LV_snap_tree ###


def main():
    g_status = 0
    g_level = 1
    g_processed = []

    # print command line arguments
    print( "the number of arguments is %d" % len(sys.argv) )
    #for arg in sys.argv[1:]:
    #    print(arg)

    if len(sys.argv) == 3:
        G_IN_WARNING = int(sys.argv[1])
        G_IN_CRITICAL = int(sys.argv[2])
    else:
        G_IN_WARNING = 75
        G_IN_CRITICAL = 90

    print(" the values are arg. count=%d  G_IN_WARNING=%d G_IN_CRITICAL=%d" % (len(sys.argv), G_IN_WARNING, G_IN_CRITICAL) )

    for vg in FN_VG_get():
        g_level = 0
        g_processed = []
    
        G_LV_LIST_TUPLE=FN_LV_get(vg)
    
        #print( G_LV_LIST_TUPLE )
        #print( "- - - - - - - - - - - - - \n\n" )
    
        ## iterate through all LVs ##
        for L_LIST_IND, l_tuple in enumerate(G_LV_LIST_TUPLE) :
            (lv_name,lv_size,data_percent,metadata_percent,snap_percent,lv_when_full,time,lv_descendants,origin,lv_attr) = G_LV_LIST_TUPLE[L_LIST_IND]
            #print( "FN_LV_snap_tree( "+ vg +", "+ lv_name +")" )
            g_status = FN_LV_snap_tree( vg, lv_name, G_LV_LIST_TUPLE, g_level, g_status, g_processed, G_IN_WARNING, G_IN_CRITICAL)
    
    return g_status
    ### End of main ###


if __name__ == "__main__":
    exit_status = main()

    #FN_LV_header()

    print( "the value of exit_status is " +str(exit_status) )
    sys.exit( exit_status )
